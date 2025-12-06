import argparse
import asyncio
import asyncio.subprocess
import contextlib
import datetime
from collections.abc import Awaitable, Callable
import json
import logging
import os
import random
import re
import shutil
import threading
import time
import sys

script_directory = os.path.dirname(os.path.abspath(__file__))
default_env_dirs = {
    "DECKY_PLUGIN_LOG_DIR": os.path.join(script_directory, "tmp", "logs"),
    "DECKY_PLUGIN_SETTINGS_DIR": os.path.join(script_directory, "tmp", "config"),
    "DECKY_PLUGIN_RUNTIME_DIR": os.path.join(script_directory, "tmp", "runtime"),
}
cli_env_defaults_applied = False
for env_key, default_path in default_env_dirs.items():
    current_value = os.environ.get(env_key)
    if not current_value:
        os.environ[env_key] = default_path
        current_value = default_path
        cli_env_defaults_applied = True
    try:
        os.makedirs(current_value, exist_ok=True)
    except OSError:
        pass

# The decky plugin module is located at decky-loader/plugin
# For easy intellisense checkout the decky-loader code repo
# and add the `decky-loader/plugin/imports` path to `python.analysis.extraPaths` in `.vscode/settings.json`
IS_CLI_ENV = cli_env_defaults_applied

try:
    import decky  # type: ignore
except ModuleNotFoundError:
    IS_CLI_ENV = True
    logging.basicConfig(level=logging.INFO)

    class _DummyLogger:
        """Lightweight logger so CLI runs do not crash when decky is missing."""

        def __init__(self):
            self._logger = logging.getLogger("decky-cli")

        def info(self, msg, *args):
            self._logger.info(msg, *args)

        def warning(self, msg, *args):
            self._logger.warning(msg, *args)

        def error(self, msg, *args):
            self._logger.error(msg, *args)

        def debug(self, msg, *args):
            self._logger.debug(msg, *args)

    class _DummyDecky:
        """Fallback decky shim for running the script outside Decky."""

        def __init__(self):
            self.logger = _DummyLogger()
            self.DECKY_USER_HOME = os.path.expanduser("~")
            self.DECKY_HOME = os.path.join(self.DECKY_USER_HOME, ".decky")

        def migrate_logs(self, *_args, **_kwargs):
            self.logger.debug("Skipping decky.migrate_logs in CLI mode")

        def migrate_settings(self, *_args, **_kwargs):
            self.logger.debug("Skipping decky.migrate_settings in CLI mode")

        def migrate_runtime(self, *_args, **_kwargs):
            self.logger.debug("Skipping decky.migrate_runtime in CLI mode")

    decky = _DummyDecky()

try:
    from settings import SettingsManager  # type: ignore
except ModuleNotFoundError:

    class SettingsManager:
        """Simple JSON-backed settings manager for CLI mode."""

        def __init__(self, name: str, settings_directory: str | None = None):
            self.name = name
            self.settings_directory = settings_directory
            self.settings_path = os.path.join(self.settings_directory, ".plugin-config.json")
            self._settings: dict[str, object] = {}

        def read(self):
            try:
                with open(self.settings_path, "r", encoding="utf-8") as infile:
                    self._settings = json.load(infile)
            except FileNotFoundError:
                self._settings = {}
            except json.JSONDecodeError:
                self._settings = {}

        def _write(self):
            os.makedirs(os.path.dirname(self.settings_path), exist_ok=True)
            with open(self.settings_path, "w", encoding="utf-8") as outfile:
                json.dump(self._settings, outfile, indent=2)

        def getSetting(self, key, default=None):
            return self._settings.get(key, default)

        def setSetting(self, key, value):
            self._settings[key] = value
            self._write()

# Determine script path
# Get environment variables with CLI-friendly defaults
logDir = os.environ.get("DECKY_PLUGIN_LOG_DIR", os.path.join(script_directory, "tmp", "logs"))
settingsDir = os.environ.get("DECKY_PLUGIN_SETTINGS_DIR", os.path.join(script_directory, "tmp", "config"))
os.makedirs(logDir, exist_ok=True)
os.makedirs(settingsDir, exist_ok=True)

if IS_CLI_ENV:
    log_path_hint = getattr(decky, "DECKY_PLUGIN_LOG", os.path.join(logDir, "decky.log"))
    #print(f"[decky-virtual-surround-sound] Log file: {log_path_hint}")

# Read settings
settings = SettingsManager(name="settings", settings_directory=settingsDir)
settings.read()

# Configure other plugin files and directories
hrir_directory = os.path.join(script_directory, "hrir-audio")
default_hrir_file = "HRTF from Aureal Vortex 2 - WIP v2.wav"
pipewire_config_path = os.path.join(os.path.expanduser("~"), ".config", "pipewire")
hrir_dest_path = os.path.join(pipewire_config_path, "hrir.wav")
sofa_directory = os.path.join(script_directory, "hrtf-sofa")
sofa_dest_path = os.path.join(pipewire_config_path, "hrir.sofa")

VIRTUAL_SURROUND_FILTER_SINK_NODE = "input.virtual-surround-sound-filter"
VIRTUAL_SURROUND_DEVICE_SINK_NODE = "input.virtual-surround-sound-input"
VIRTUAL_SURROUND_FALLBACK_SINK_NODE = "input.virtual-sink"


def subprocess_exec_env():
    uid = os.getuid()
    if uid not in (1000, 1001):
        decky.logger.warning("Attempting to run subprocess as uid %s. Looks like something is going wrong here.", uid)
    allowed_keys = [
        "DBUS_SESSION_BUS_ADDRESS", "HOME", "LANG", "PATH", "SHELL", "USER",
        "XDG_DATA_DIRS", "XDG_RUNTIME_DIR", "XDG_SESSION_CLASS", "XDG_SESSION_ID", "XDG_SESSION_TYPE",
    ]
    env = {key: os.environ[key] for key in allowed_keys if key in os.environ}
    env['XDG_RUNTIME_DIR'] = f"/run/user/{uid}"
    env['DBUS_SESSION_BUS_ADDRESS'] = f"unix:path=/run/user/{uid}/bus"
    return env


async def service_script_exec(command, args=None):
    if args is None:
        args = []
    service_script = os.path.join(script_directory, "service.sh")
    try:
        process = await asyncio.create_subprocess_exec(
            service_script, command, *args,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
            env=subprocess_exec_env()
        )
        stdout, stderr = await process.communicate()
        if process.returncode != 0:
            decky.logger.error(f"Service script exec failed: {stderr.decode()}")
        else:
            decky.logger.info("Service script exec output:")
            for line in stdout.decode().splitlines():
                decky.logger.info(line)
    except Exception as e:
        decky.logger.error(f"Error executing service script: {e}")


async def async_wait(evt: asyncio.Event, timeout: float) -> bool:
    with contextlib.suppress(asyncio.TimeoutError):
        await asyncio.wait_for(evt.wait(), timeout)
    return evt.is_set()


class Plugin:
    IGNORED_APP_BINARIES = {"steamwebhelper"}

    def __init__(self):
        self._background_task = None
        self.stop_event = asyncio.Event()

    # Asyncio-compatible long-running code, executed in a task when the plugin is loaded
    async def _main(self):
        self.loop = asyncio.get_event_loop()

        # Install initial files
        await self.init_config()

        self.stop_event.clear()
        # Start the background task.
        self._background_task = self.loop.create_task(self.background_tasks())
        decky.logger.info("Plugin main started")

    # Function called first during the unload process, utilize this to handle your plugin being stopped, but not
    # completely removed
    async def _unload(self):
        decky.logger.info("Unloading plugin: stopping background tasks...")
        # Signal the background task to exit.
        self.stop_event.set()
        if self._background_task:
            self._background_task.cancel()
            try:
                await self._background_task
            except asyncio.CancelledError:
                decky.logger.info("Background task cancelled successfully")
        decky.logger.info("Plugin unloaded")

    # Function called after `_unload` during uninstall, utilize this to clean up processes and other remnants of your
    # plugin that may remain on the system
    async def _uninstall(self):
        decky.logger.info("Uninstalling service as background task")
        timestamp = datetime.datetime.now().strftime("%Y-%m-%d_%H.%M.%S")
        uninstall_log_path = os.path.join(logDir, f"uninstall_{timestamp}.log")
        service_script = os.path.join(script_directory, "service.sh")
        cmd = f"{service_script} uninstall &> {uninstall_log_path}"
        os.spawnle(os.P_NOWAIT, "/bin/sh", "sh", "-c", cmd, subprocess_exec_env())
        # Clean up the HRIR file if it exists.
        decky.logger.info("Removing '%s' if it exists", hrir_dest_path)
        if os.path.exists(hrir_dest_path):
            os.remove(hrir_dest_path)
        decky.logger.info("Plugin uninstalled")

    # Migrations that should be performed before entering `_main()`.
    async def _migration(self):
        decky.logger.info("Migrating")
        # Here's a migration example for logs:
        # - `~/.config/decky-template/template.log` will be migrated to `decky.decky_LOG_DIR/template.log`
        decky.migrate_logs(os.path.join(decky.DECKY_USER_HOME,
                                        ".config", "decky-template", "template.log"))
        # Here's a migration example for settings:
        # - `~/homebrew/settings/template.json` is migrated to `decky.decky_SETTINGS_DIR/template.json`
        # - `~/.config/decky-template/` all files and directories under this root are migrated to `decky.decky_SETTINGS_DIR/`
        decky.migrate_settings(
            os.path.join(decky.DECKY_HOME, "settings", "template.json"),
            os.path.join(decky.DECKY_USER_HOME, ".config", "decky-template"))
        # Here's a migration example for runtime data:
        # - `~/homebrew/template/` all files and directories under this root are migrated to `decky.decky_RUNTIME_DIR/`
        # - `~/.local/share/decky-template/` all files and directories under this root are migrated to `decky.decky_RUNTIME_DIR/`
        decky.migrate_runtime(
            os.path.join(decky.DECKY_HOME, "template"),
            os.path.join(decky.DECKY_USER_HOME, ".local", "share", "decky-template"))

    async def background_tasks(self):
        decky.logger.info("Background tasks started")
        while not self.stop_event.is_set():
            try:
                decky.logger.info("Running task to ensure applications are assigned to their configured sinks")
                await self.check_state()
                # Wait for 30 seconds, or exit early if stop_event is set.
                try:
                    await asyncio.wait_for(self.stop_event.wait(), timeout=30)
                except asyncio.TimeoutError:
                    # Timeout occurred: continue loop.
                    pass
            except asyncio.CancelledError:
                decky.logger.info("Background task cancelled")
                break
            except Exception as e:
                decky.logger.error(f"[background_tasks error]: {e}")
        decky.logger.info("Background tasks stopped")

    async def init_config(self):
        if not os.path.exists(os.path.join(pipewire_config_path, "hrir.wav")):
            decky.logger.info("Installing default HRIR .wav file '%s'", default_hrir_file)
            await self.set_hrir_file(os.path.join(hrir_directory, default_hrir_file))
        decky.logger.info("Installing service")
        await service_script_exec("install")

    async def get_surround_sink_default(self):
        """Checks if the Virtual Surround Sound sink should be the default"""
        return settings.getSetting("surround_sink_default", True)

    async def enable_surround_sink_default(self):
        """Sets the Virtual Surround Sound sink as the default"""
        decky.logger.info("Enabling Virtual Surround Sound as the default sink")
        settings.setSetting("surround_sink_default", True)
        await self.check_state()
        return True

    async def disable_surround_sink_default(self):
        """Disables the Virtual Surround Sound sink as the default"""
        decky.logger.info("Removing Virtual Surround Sound as the default sink")
        settings.setSetting("surround_sink_default", False)
        await self.check_state()
        return True

    async def get_enabled_apps_list(self):
        """Reads the current list of enabled apps"""
        return settings.getSetting("enabled_apps", [])

    async def enable_for_app(self, app_name: str):
        """Adds a given app name to the list of enabled apps"""
        decky.logger.info("Enabling Virtual Surround Sound for app %s", app_name)
        enabled_apps = settings.getSetting("enabled_apps", [])
        if app_name not in enabled_apps:
            enabled_apps.append(app_name)
            settings.setSetting("enabled_apps", enabled_apps)
            decky.logger.info("App %s enabled.", app_name)
            await self.check_state()
        else:
            decky.logger.info("App %s was already enabled.", app_name)
        return True

    async def disable_for_app(self, app_name: str):
        """Removes a given app name from the list of enabled apps"""
        decky.logger.info("Disabling Virtual Surround Sound for app %s", app_name)
        enabled_apps = settings.getSetting("enabled_apps", [])
        if app_name in enabled_apps:
            updated_list = [a for a in enabled_apps if a != app_name]
            settings.setSetting("enabled_apps", updated_list)
            decky.logger.info("App %s disabled.", app_name)
            await self.check_state()
        else:
            decky.logger.info("App %s was not enabled.", app_name)
        return True

    async def check_state(self):
        settings.read()
        enabled_apps = await self.get_enabled_apps_list()
        sinks = await self.list_sinks() or []
        sink_inputs = await self.list_sink_inputs()
        if not isinstance(sink_inputs, list):
            sink_inputs = []

        # Find the sinks for "Virtual Surround Sound" and "Virtual Sink"
        virtual_surround_filter_sink = next((sink for sink in sinks if sink.get("name")
                                     == VIRTUAL_SURROUND_FILTER_SINK_NODE), None)
        virtual_surround_device_sink = next((sink for sink in sinks if sink.get("name")
                                             == VIRTUAL_SURROUND_DEVICE_SINK_NODE), None)
        virtual_sink = next((sink for sink in sinks if sink.get("name") == VIRTUAL_SURROUND_FALLBACK_SINK_NODE), None)
        if not virtual_surround_filter_sink:
            decky.logger.error("Required sink not found. Virtual Surround Sound is missing.")
            return
        if not virtual_sink:
            decky.logger.warning("Virtual Sink is missing. Will attempt to detect the current default sink instead.")

        virtual_surround_object_id = self._object_id_from_sink(virtual_surround_filter_sink)
        virtual_surround_index = self._sink_index_from_entry(virtual_surround_filter_sink)
        if virtual_surround_object_id is None or virtual_surround_index is None:
            decky.logger.error("Virtual Surround Sound sink is missing required metadata.")
            return
        virtual_surround_device_object_id = self._object_id_from_sink(virtual_surround_device_sink)
        virtual_surround_device_index = self._sink_index_from_entry(virtual_surround_device_sink)
        virtual_surround_target_index = virtual_surround_device_index if virtual_surround_device_index is not None else virtual_surround_index

        # Determine the default_sink_id and default_sink_index
        default_sink_id: int | None = None
        default_sink_index: int | None = None
        default_sink_entry = virtual_sink
        if virtual_sink:
            default_sink_id = self._object_id_from_sink(virtual_sink)
            default_sink_index = self._sink_index_from_entry(virtual_sink)
            if default_sink_id is None or default_sink_index is None:
                decky.logger.warning("Virtual Sink is missing metadata; unable to use as fallback.")
                default_sink_id = None
                default_sink_index = None
                default_sink_entry = None

        if default_sink_id is None or default_sink_index is None:
            fallback_sink_id = await self.get_highest_priority_sink_id()
            if fallback_sink_id is not None:
                fallback_sink = next(
                    (sink for sink in sinks if self._object_id_from_sink(sink) == fallback_sink_id),
                    None
                )
                if fallback_sink:
                    default_sink_id = self._object_id_from_sink(fallback_sink)
                    default_sink_index = self._sink_index_from_entry(fallback_sink)
                    default_sink_entry = fallback_sink
                    decky.logger.info(
                        "Using highest priority sink (object %s, index %s).",
                        default_sink_id, default_sink_index
                    )
                else:
                    decky.logger.warning(
                        "Fallback sink object id %s not found; cannot determine sink index.",
                        fallback_sink_id
                    )
            if default_sink_id is None or default_sink_index is None:
                decky.logger.warning("Unable to determine fallback default sink; leaving default unchanged.")

        # Ensure that the "Virtual Surround Sound" is default
        use_surround_sink_as_default = await self.get_surround_sink_default()
        if use_surround_sink_as_default:
            if virtual_surround_device_object_id is not None:
                await self.set_default_sink(virtual_surround_device_object_id)
            else:
                decky.logger.warning("Virtual Surround Device sink id not resolved; cannot update default sink.")
        else:
            if default_sink_id is not None:
                await self.set_default_sink(default_sink_id)
            else:
                decky.logger.warning("Default sink id not resolved; cannot update default sink.")

        # Loop over each sink input and check its assignment.
        surround_sink_indices: set[int] = set()
        if virtual_surround_index is not None:
            surround_sink_indices.add(virtual_surround_index)
        if virtual_surround_device_index is not None:
            surround_sink_indices.add(virtual_surround_device_index)
        for sink_input in sink_inputs:
            target_object = self._sink_input_target_object(sink_input)
            if target_object.strip():
                continue

            app_name = self._sink_input_app_name(sink_input)
            if not app_name:
                continue

            current_sink_index = sink_input.get('sink')
            # If the app is in the enabled_apps list,
            # it should be assigned to the Virtual Surround Sound sink.
            if app_name in enabled_apps:
                if virtual_surround_target_index is None:
                    decky.logger.warning(
                        "Unable to assign %s to Virtual Surround Sound: sink index unavailable.",
                        app_name,
                    )
                    continue
                if current_sink_index != virtual_surround_target_index:
                    decky.logger.info(
                        "Moving %s (sink input %s) to Virtual Surround Sound (sink %s)",
                        app_name, sink_input['index'], virtual_surround_target_index
                    )
                    await self.set_sink_for_application(sink_input['index'], virtual_surround_target_index)
            else:
                # If the app is not enabled but is currently assigned to the Virtual Surround Sound sink,
                # move it to the Virtual Sink.
                if current_sink_index in surround_sink_indices:
                    if default_sink_index is None:
                        decky.logger.warning(
                            "Default sink index unresolved; cannot move %s to fallback sink.", app_name
                        )
                        continue
                    decky.logger.info(
                        "Moving %s (sink input %s) to fallback sink (sink %s)",
                        app_name, sink_input['index'], default_sink_index
                    )
                    await self.set_sink_for_application(sink_input['index'], default_sink_index)

    async def get_hrir_file_list(self) -> list[dict[str, str | None | int]] | None:
        """Lists available HRIR files with channel count."""
        hrir_files = []
        i = 1
        # Check if ffprobe is installed
        try:
            process = await asyncio.create_subprocess_exec(
                "ffprobe", "-version",
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
                env=subprocess_exec_env()
            )
            await process.communicate()
            ffprobe = process.returncode == 0
        except FileNotFoundError:
            decky.logger.warning("ffprobe not found. HRIR channel detection will be skipped.")
            ffprobe = False
        except Exception as e:
            decky.logger.error(f"Error checking ffprobe: {e}")
            ffprobe = False
        for filename in os.listdir(hrir_directory):
            if filename.endswith(".wav") and os.path.isfile(os.path.join(hrir_directory, filename)):
                filepath = os.path.join(hrir_directory, filename)
                channel_count = None
                try:
                    if ffprobe:
                        process = await asyncio.create_subprocess_exec(
                            "ffprobe", "-v", "error", "-select_streams", "a:0", "-show_entries", "stream=channels",
                            "-of", "default=noprint_wrappers=1:nokey=1", filepath,
                            stdout=asyncio.subprocess.PIPE,
                            stderr=asyncio.subprocess.PIPE,
                            env=subprocess_exec_env()
                        )
                        stdout, stderr = await process.communicate()
                        if process.returncode != 0:
                            decky.logger.error(f"ffprobe failed for {filename}: {stderr.decode()}")
                        else:
                            channel_count = int(stdout.decode().strip())
                except (ValueError, FileNotFoundError) as e:
                    channel_count = None
                finally:
                    hrir_files.append({
                        "label": os.path.basename(filepath)[:-4],
                        "path": filepath,
                        "channel_count": channel_count
                    })
                    i += 1
        if hrir_files:
            hrir_files.sort(key=lambda x: (x["channel_count"] is not None, x["channel_count"] or 0, x["path"]),
                            reverse=False)
        return hrir_files

    async def set_hrir_file(self, selected_hrir_path: str) -> bool:
        """Installs the specified HRIR file."""
        decky.logger.info("Installing %s", selected_hrir_path)
        try:
            os.makedirs(os.path.dirname(hrir_dest_path), exist_ok=True)
            shutil.copy2(selected_hrir_path, hrir_dest_path)
            os.chmod(hrir_dest_path, 0o644)
            decky.logger.info("Copied %s to %s", selected_hrir_path, hrir_dest_path)
            await service_script_exec("restart")
            return True
        except Exception as e:
            decky.logger.error("Error: Failed to copy HRIR WAV file: %s", e)
        return False

    async def get_sofa_file_list(self) -> list[dict[str, str | None | int]] | None:
        """Lists available SOFA files."""
        sofa_files: list[dict[str, str | None | int]] = []
        try:
            os.makedirs(sofa_directory, exist_ok=True)
        except OSError:
            pass
        for filename in os.listdir(sofa_directory):
            if filename.endswith(".sofa") and os.path.isfile(os.path.join(sofa_directory, filename)):
                filepath = os.path.join(sofa_directory, filename)
                file_size: int | None
                try:
                    file_size = os.path.getsize(filepath)
                except OSError:
                    file_size = None
                sofa_files.append({
                    "label": os.path.splitext(os.path.basename(filepath))[0],
                    "path": filepath,
                    "size": file_size
                })
        if sofa_files:
            sofa_files.sort(key=lambda x: x.get("label") or "")
        return sofa_files

    async def set_sofa_file(self, selected_sofa_path: str) -> bool:
        """Installs the specified SOFA file."""
        decky.logger.info("Installing %s", selected_sofa_path)
        try:
            os.makedirs(os.path.dirname(sofa_dest_path), exist_ok=True)
            shutil.copy2(selected_sofa_path, sofa_dest_path)
            os.chmod(sofa_dest_path, 0o644)
            decky.logger.info("Copied %s to %s", selected_sofa_path, sofa_dest_path)
            await service_script_exec("restart")
            return True
        except Exception as e:
            decky.logger.error("Error: Failed to copy SOFA file: %s", e)
        return False

    async def run_sound_test(self, sink: str):
        """Run a surround sound test using the sink specified"""
        await service_script_exec("speaker-test", ["--sink", sink])

    @staticmethod
    def _sink_input_properties(sink_input: dict | None) -> dict:
        if not sink_input:
            return {}
        props = sink_input.get("properties")
        if isinstance(props, dict):
            return props
        return {}

    @staticmethod
    def _clean_application_name(name_value) -> str | None:
        if isinstance(name_value, str):
            cleaned = name_value.strip()
            if cleaned and cleaned.lower() != "(null)":
                return cleaned
        return None

    def _normalize_sink_input(self, sink_input: dict | None) -> dict | None:
        if not isinstance(sink_input, dict):
            return None
        props = self._sink_input_properties(sink_input)
        if self._sink_input_binary_is_ignored(props):
            return None
        normalized = dict(sink_input)
        normalized["properties"] = props
        normalized["target_object"] = props.get("target.object", "")
        app_name = self._clean_application_name(props.get("application.name"))
        if app_name:
            normalized["name"] = app_name
        normalized["format"] = self._parse_format_description(sink_input)
        normalized["volume"] = self._sink_input_volume_description(sink_input)
        return normalized

    def _sink_input_binary_is_ignored(self, props: dict) -> bool:
        binary = props.get("application.process.binary")
        if not isinstance(binary, str) or not binary.strip():
            return True
        return binary in self.IGNORED_APP_BINARIES

    def _parse_format_description(self, sink_input: dict | None) -> dict:
        format_string = ""
        sample_spec = ""
        channel_map_value = None
        if isinstance(sink_input, dict):
            if isinstance(sink_input.get("format"), str):
                format_string = sink_input.get("format", "")
            if isinstance(sink_input.get("sample_specification"), str):
                sample_spec = sink_input.get("sample_specification", "")
            channel_map_value = sink_input.get("channel_map")
        base_format = format_string.split(",", 1)[0].strip() if format_string else ""
        sample_format = self._extract_format_field(format_string, r'format\.sample_format\s*=\s*"((?:\\.|[^"])*)"')
        rate = self._extract_format_field(format_string, r'format\.rate\s*=\s*"((?:\\.|[^"])*)"')
        channels = self._extract_format_field(format_string, r'format\.channels\s*=\s*"((?:\\.|[^"])*)"')
        extracted_map = self._extract_format_field(format_string, r'format\.channel_map\s*=\s*"((?:\\.|[^"])*)"')
        channel_map = self._parse_channel_map(
            extracted_map) if extracted_map else self._parse_channel_map(channel_map_value)

        if sample_spec:
            if not sample_format:
                sample_format = sample_spec.split()[0].strip()
            if not rate:
                rate_match = re.search(r'(\d+)\s*Hz', sample_spec, re.IGNORECASE)
                rate = rate_match.group(1) if rate_match else rate
            if not channels:
                channels_match = re.search(r'(\d+)ch', sample_spec, re.IGNORECASE)
                channels = channels_match.group(1) if channels_match else channels

        return {
            "format": base_format or sample_format or "",
            "sample_format": sample_format or "",
            "rate": rate or "",
            "channels": channels or "",
            "channel_map": channel_map or [],
        }

    @staticmethod
    def _extract_format_field(format_string: str, pattern: str) -> str:
        if not format_string:
            return ""
        match = re.search(pattern, format_string)
        if not match:
            return ""
        return Plugin._clean_format_token(match.group(1))

    @staticmethod
    def _clean_format_token(value: str | None) -> str:
        if not value:
            return ""
        try:
            decoded = bytes(value, "utf-8").decode("unicode_escape")
        except UnicodeDecodeError:
            decoded = value
        cleaned = decoded.strip()
        if cleaned.startswith('"') and cleaned.endswith('"'):
            cleaned = cleaned[1:-1].strip()
        return cleaned

    @staticmethod
    def _parse_channel_map(value) -> list[str]:
        if isinstance(value, list):
            return [str(item).strip() for item in value if str(item).strip()]
        if isinstance(value, str):
            cleaned = Plugin._clean_format_token(value)
            return [part.strip() for part in cleaned.split(",") if part.strip()]
        return []

    def _sink_input_app_name(self, sink_input: dict | None) -> str | None:
        props = self._sink_input_properties(sink_input)
        if not props:
            return None
        if props.get("application.process.binary") == "steamwebhelper":
            return None
        name = self._clean_application_name(props.get("application.name"))
        if name:
            return name
        media_name = props.get("media.name")
        if isinstance(media_name, str) and media_name.strip():
            return media_name
        return None

    @staticmethod
    def _sink_input_target_object(sink_input: dict | None) -> str:
        props = Plugin._sink_input_properties(sink_input)
        target_object = props.get("target.object", "")
        if isinstance(target_object, str):
            return target_object
        return ""

    @staticmethod
    def _sink_input_volume_description(sink_input: dict | None) -> str:
        volume = sink_input.get("volume") if sink_input else None
        if not isinstance(volume, dict):
            return ""
        entries = []
        for channel, details in volume.items():
            if not isinstance(details, dict):
                continue
            percent = details.get("value_percent")
            if isinstance(percent, str) and percent:
                entries.append(f"{channel}: {percent}")
        return ", ".join(entries)

    def _parse_plain_sink_input_names(self, output: str) -> dict[int, str]:
        names: dict[int, str] = {}
        current_index: int | None = None
        for raw_line in output.splitlines():
            stripped = raw_line.strip()
            if not stripped:
                continue
            index_match = re.match(r"Sink Input #(\d+)", stripped)
            if index_match:
                try:
                    current_index = int(index_match.group(1))
                except ValueError:
                    current_index = None
                continue
            if current_index is None:
                continue
            app_match = re.match(r'application\.name\s*=\s*"([^"]*)"', stripped)
            if app_match:
                cleaned = self._clean_application_name(app_match.group(1))
                if cleaned:
                    names[current_index] = cleaned
                continue
            node_match = re.match(r'node\.name\s*=\s*"([^"]*)"', stripped)
            if node_match and current_index not in names:
                cleaned = self._clean_application_name(node_match.group(1))
                if cleaned:
                    names[current_index] = cleaned
        return names

    @staticmethod
    def _parse_int(value, default: int = 0) -> int:
        try:
            return int(value)
        except (TypeError, ValueError):
            return default

    @staticmethod
    def _object_id_from_sink(sink_entry: dict | None) -> int | None:
        if not sink_entry:
            return None
        props = sink_entry.get("properties") or {}
        try:
            object_id = int(props.get("object.id"))
            return object_id if object_id >= 0 else None
        except (TypeError, ValueError):
            return None

    @staticmethod
    def _sink_index_from_entry(sink_entry: dict | None) -> int | None:
        if not sink_entry:
            return None
        try:
            index = int(sink_entry.get("index"))
            return index if index >= 0 else None
        except (TypeError, ValueError):
            return None

    @staticmethod
    def _channel_map_from_sink(sink_entry: dict | None) -> list[str]:
        if not sink_entry:
            return []
        channel_map = sink_entry.get("channel_map")
        if isinstance(channel_map, list):
            return [str(item).strip() for item in channel_map if str(item).strip()]
        if isinstance(channel_map, str):
            return [part.strip() for part in channel_map.split(",") if part.strip()]
        return []

    @staticmethod
    def _sink_display_name(sink_entry: dict | None) -> str:
        if not sink_entry:
            return "unknown sink"
        props = sink_entry.get("properties") or {}
        return props.get("node.description") or sink_entry.get("description") or sink_entry.get("name") or "unknown sink"

    async def get_highest_priority_sink_id(self) -> int | None:
        """
        Returns the object ID of the sink with the highest priority.session value.
        Ports marked as "not available" for every entry are treated as priority 0.
        """
        sinks = await self.list_sinks()
        if not sinks:
            decky.logger.warning("Unable to determine priority sink: no sinks reported.")
            return None

        best_sink_id: int | None = None
        best_priority = -1
        best_index = -1

        for sink in sinks:
            obj_id = self._object_id_from_sink(sink)
            if obj_id is None:
                continue

            # Get the sink index
            sink_index = self._parse_int(sink.get("index"), -1)

            # Get sink properties
            properties = sink.get("properties") or {}

            # Skip virtual sinks
            if properties.get("node.virtual") == "true":
                continue

            # Get session priority
            session_priority = self._parse_int(properties.get("priority.session"), -1)

            # Ensure sink has eligible port (Note: WirePlumber will consider ports that are marked as "unknown" as eligible for selection)
            # Anything with an availablility "not available" on all ports should be considered of a low priority
            ports = sink.get("ports") or []
            effective_priority = session_priority
            if ports:
                availabilities = [
                    str(port.get("availability") or "").strip().lower()
                    for port in ports
                ]
                if availabilities and all(value == "not available" for value in availabilities):
                    effective_priority = 0

            # Determine the priority
            if effective_priority > best_priority or (
                effective_priority == best_priority and sink_index > best_index
            ):
                best_priority = effective_priority
                best_index = sink_index
                best_sink_id = obj_id

        if best_sink_id is None:
            decky.logger.warning("No suitable sinks with priority.session found.")
            return None

        return best_sink_id

    async def get_default_sink_id(self) -> int | None:
        """
        Returns the object ID of the current default sink as reported by pactl.
        """
        default_sink_name = await self.get_default_sink_name()
        sinks = await self.list_sinks()
        if not sinks:
            return None
        if not default_sink_name:
            return None

        default_sink = next((s for s in sinks if s.get("name") == default_sink_name), None)
        if not default_sink:
            decky.logger.warning("Default sink '%s' not found in pactl list.", default_sink_name)
            return None

        object_id = self._object_id_from_sink(default_sink)
        if object_id is None:
            decky.logger.warning("Default sink '%s' is missing a valid object.id.", default_sink_name)
            return None

        decky.logger.debug(
            "Using default sink '%s' (object_id=%s index=%s)",
            default_sink_name,
            object_id,
            default_sink.get("index"),
        )
        return object_id

    async def get_default_sink_name(self) -> str | None:
        """
        Returns the sink name reported by `pactl get-default-sink`.
        """
        try:
            process = await asyncio.create_subprocess_exec(
                'pactl', 'get-default-sink',
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
                env=subprocess_exec_env()
            )
            stdout, stderr = await process.communicate()
            if process.returncode != 0:
                decky.logger.error("pactl get-default-sink failed: %s", stderr.decode().strip())
                return None
            output = stdout.decode().strip()
            if not output:
                return None
            first_line = output.splitlines()[0].strip()
            match = re.search(r'(?:default(?:\s+sink)?)\s*[:=]\s*(\S+)', first_line, re.IGNORECASE)
            if match:
                return match.group(1)
            return first_line
        except FileNotFoundError:
            decky.logger.error("pactl not found when requesting default sink.")
            return None
        except Exception as e:
            decky.logger.error("Error retrieving default sink: %s", e)
            return None

    async def list_sinks(self):
        """
        Retrieve a mapping of sink index to its name and description.
        """
        sinks = []
        try:
            process = await asyncio.create_subprocess_exec(
                'pactl', '-f', 'json', 'list', 'sinks',
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
                env=subprocess_exec_env()
            )
            stdout, stderr = await process.communicate()
            if process.returncode != 0:
                decky.logger.error(f"pactl list sinks failed: {stderr.decode()}")
                return []

            try:
                return json.loads(stdout.decode())
            except json.JSONDecodeError as exc:
                decky.logger.error(f"Failed to decode pactl sinks JSON: {exc}")
                return []
        except FileNotFoundError:
            decky.logger.error("pactl not found.")
            return []
        except Exception as e:
            decky.logger.error(f"Error getting sinks: {e}")
            return []
        return sinks

    async def list_sink_inputs(self):
        """
        Retrieve sink inputs (running application audio streams) using pactl's JSON output.
        Returns a normalized list that includes parsed format details and friendly metadata.
        """
        try:
            process = await asyncio.create_subprocess_exec(
                'pactl', '-f', 'json', 'list', 'sink-inputs',
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
                env=subprocess_exec_env()
            )
            stdout, stderr = await process.communicate()
            if process.returncode != 0:
                decky.logger.error("pactl list sink-inputs failed: %s", stderr.decode().strip())
                return []
            try:
                raw_inputs = json.loads(stdout.decode())
            except json.JSONDecodeError as exc:
                decky.logger.error("Failed to decode pactl sink inputs JSON: %s", exc)
                return []
            normalized_inputs = []
            for entry in raw_inputs:
                normalized = self._normalize_sink_input(entry)
                if normalized:
                    normalized_inputs.append(normalized)
            if normalized_inputs:
                # NOTE: For some reason the JSON formatted output of pactl had decode errors for some app names.
                #   I could not figure out how to fix that, so I am going to run it twice, the second time without JSON formatting.
                #   Not ideal, but whatever.
                process = await asyncio.create_subprocess_exec(
                    'pactl', 'list', 'sink-inputs',
                    stdout=asyncio.subprocess.PIPE,
                    stderr=asyncio.subprocess.PIPE,
                    env=subprocess_exec_env()
                )
                stdout, stderr = await process.communicate()
                if process.returncode != 0:
                    decky.logger.error("pactl list sink-inputs (text) failed: %s", stderr.decode().strip())
                    name_map = {}
                else:
                    name_map = self._parse_plain_sink_input_names(stdout.decode())
                    if name_map:
                        for entry in normalized_inputs:
                            sink_index = self._parse_int(entry.get("index"), -1)
                            if sink_index < 0:
                                continue
                            new_name = self._clean_application_name(name_map.get(sink_index))
                            if not new_name:
                                continue
                            existing = self._clean_application_name(entry.get("name"))
                            if existing:
                                continue
                            entry["name"] = new_name
            return normalized_inputs
        except FileNotFoundError:
            decky.logger.error("pactl not found.")
            return []
        except Exception as e:
            decky.logger.error(f"Error getting sink inputs: {e}")
            return []

    async def set_default_sink(self, sink_input_index: str):
        """Moves the sink output for the given app"""
        try:
            process = await asyncio.create_subprocess_exec(
                "wpctl", 'set-default', str(sink_input_index),
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
                env=subprocess_exec_env()
            )
            stdout, stderr = await process.communicate()
            if process.returncode != 0:
                decky.logger.error(
                    "Failed to set default sink to %s: %s",
                    sink_input_index,
                    stderr.decode().strip(),
                )
                return False
            decky.logger.info(
                "Default sink set via wpctl to %s. %s",
                sink_input_index,
                stdout.decode().strip(),
            )
            return True
        except FileNotFoundError:
            decky.logger.warning("wpctl not found.")
            return False
        except Exception as e:
            decky.logger.error(f"Error setting default input sink: {e}")
            return False

    async def set_sink_for_application(self, sink_input_index: str, target_sink_index: str):
        """Moves the sink output for the given app"""
        #  > pactl list sink-inputs
        # Plex - Sink Input #649
        # Plex -         Sink: 50
        #
        #  > pactl list sinks
        # Virtual Sink: 50
        # Virtual Surround Sound Sink: 57
        #
        #  > pactl move-sink-input 649 50
        #  > pactl move-sink-input 1790 49
        #  > pactl move-sink-input 1868 433
        #  > pactl move-sink-input 1868 49
        try:
            process = await asyncio.create_subprocess_exec(
                "pactl", 'move-sink-input', str(sink_input_index), str(target_sink_index),
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
                env=subprocess_exec_env()
            )
            await process.communicate()
            return process.returncode == 0
        except FileNotFoundError:
            decky.logger.warning("pactl not found.")
            return False
        except Exception as e:
            decky.logger.error(f"Error moving sink input: {e}")
            return False

    async def set_mixer_profile(self, mixer_profile):
        """
        Sets per-channel volumes on the sink named "virtual-surround-sound"
        using the provided mixer_profile dict.

        The mixer_profile is expected to be a dict like:
          {
            "name": "default",
            "usePerAppProfile": false,
            "volumes": {
              "FL": 100,
              "FR": 100,
              "FC": 100,
              "LFE": 100,
              "RL": 100,
              "RR": 100,
              "SL": 100,
              "SR": 100
            }
          }
        """
        sinks = await self.list_sinks()
        target_sink = None
        for sink in sinks:
            # Look for the sink named "input.virtual-surround-sound"
            if sink.get("name") == VIRTUAL_SURROUND_FILTER_SINK_NODE:
                target_sink = sink
                break
        if target_sink is None:
            decky.logger.error("Sink 'virtual-surround-sound' not found")
            return False

        sink_index = self._sink_index_from_entry(target_sink)
        if sink_index is None:
            decky.logger.error("Sink 'virtual-surround-sound' missing sink index")
            return False

        channel_map = self._channel_map_from_sink(target_sink)
        if not channel_map:
            decky.logger.error("Channel Map not found for sink 'virtual-surround-sound'")
            return False

        # Map full channel names to short codes used in mixer_profile.
        # The pactl command will return the channels as "front-left" and "front-right".
        channel_name_map = {
            "front-left": "FL",
            "front-right": "FR",
            "front-center": "FC",
            "lfe": "LFE",
            "rear-left": "RL",
            "rear-right": "RR",
            "side-left": "SL",
            "side-right": "SR"
        }
        # Since we need to map the volume args in the correct order, we will map them based on the sink channel_map,
        # then read each channel volume provided in the mixer_profile in the correct order.
        volume_args = []
        for ch in channel_map:
            short_code = channel_name_map.get(ch)
            if short_code and short_code in mixer_profile.get("volumes", {}):
                volume_value = mixer_profile["volumes"][short_code]
                # Build a per-channel volume argument (e.g. "100%")
                volume_args.append(f"{volume_value}%")
            else:
                volume_args.append(f"100%")

        if not volume_args:
            decky.logger.error("No matching channels found in mixer profile for sink channel map")
            return False

        # Execute pactl to set the per-channel volume.
        command = ["pactl", "set-sink-volume", str(sink_index)] + volume_args
        try:
            process = await asyncio.create_subprocess_exec(
                *command,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
                env=subprocess_exec_env()
            )
            stdout, stderr = await process.communicate()
            if process.returncode != 0:
                decky.logger.error("Failed to set mixer profile: " + stderr.decode())
                return False
            decky.logger.debug(f"Mixer profile applied on sink {sink_index} with volumes: {volume_args}")
            return True
        except Exception as e:
            decky.logger.error(f"Error setting mixer profile: {e}")
            return False

    async def test_stuff(self):
        # await self._main()
        # await self._uninstall()
        # hrir_file_list = await self.get_hrir_file_list()
        # await self.set_hrir_file(hrir_file_list[0].get("path"))
        sinks = await self.list_sinks()
        print(json.dumps(sinks, indent=2))
        sink_inputs = await self.list_sink_inputs()
        print(json.dumps(sink_inputs, indent=2))

        # For testing set_mixer_profile, define a mixer_profile dict:
        mixer_profile = {
            "name": "default",
            "usePerAppProfile": False,
            "volumes": {
                "FL": 50,
                "FR": 50,
                "FC": 50,
                "LFE": 20,
                "RL": 100,
                "RR": 100,
                "SL": 80,
                "SR": 80
            }
        }
        # Uncomment to test setting the mixer profile:
        await plugin.set_mixer_profile(mixer_profile)


class CLIHelper:
    """Convenience bridge for running async plugin methods from the curses UI."""

    def __init__(self):
        self.loop = asyncio.new_event_loop()
        asyncio.set_event_loop(self.loop)
        self._lock = threading.Lock()

    def run(self, coro):
        with self._lock:
            return self.loop.run_until_complete(coro)

    def run_delayed(self, coro_factory: Callable[[], Awaitable[object]], delay: float):
        """Run coroutine returned by coro_factory after delay in seconds on a background thread."""

        def _worker():
            time.sleep(delay)
            try:
                self.run(coro_factory())
            except Exception as exc:
                logging.getLogger("cli-menu").error("Delayed task failed: %s", exc)

        threading.Thread(target=_worker, daemon=True).start()

    def close(self):
        self.loop.close()

    def lines_for_sinks(self, plugin: Plugin) -> list[str]:
        sinks = self.run(plugin.list_sinks()) or []
        lines: list[str] = []
        if not sinks:
            lines.append("No sinks found.")
            return lines
        for idx, sink in enumerate(sinks, start=1):
            sink_index = plugin._sink_index_from_entry(sink)
            object_id = plugin._object_id_from_sink(sink)
            description = sink.get("description") or "No description"
            lines.append(f"{idx}. {sink.get('name')} (index={sink_index if sink_index is not None else 'unknown'})")
            lines.append(f"    object_id: {object_id if object_id is not None else 'unknown'}")
            lines.append(f"    description: {description}")
            props = sink.get("properties") or {}
            priority = props.get("priority.session")
            if priority is not None:
                lines.append(f"    priority.session: {priority}")
            channels = plugin._channel_map_from_sink(sink)
            if channels:
                lines.append(f"    channels: {', '.join(channels)}")
        return lines

    def lines_for_running_apps(self, plugin: Plugin) -> list[str]:
        sink_inputs = self.run(plugin.list_sink_inputs()) or []
        lines: list[str] = []
        if not sink_inputs:
            lines.append("No running apps detected.")
            return lines
        for idx, entry in enumerate(sink_inputs, start=1):
            name = entry.get("name") or plugin._sink_input_app_name(entry) or f"Sink Input {entry.get('index')}"
            lines.append(f"{idx}. {name}")
            lines.append(f"    index: {entry.get('index')} -> sink {entry.get('sink')}")
            target = entry.get("target_object") or plugin._sink_input_target_object(entry)
            if target:
                lines.append(f"    target: {target}")
            volume_desc = entry.get("volume") or plugin._sink_input_volume_description(entry)
            if volume_desc:
                lines.append(f"    volume: {volume_desc}")
            format_value = entry.get("format")
            if isinstance(format_value, dict):
                fmt_parts = []
                if format_value.get("format"):
                    fmt_parts.append(f"type={format_value['format']}")
                if format_value.get("sample_format"):
                    fmt_parts.append(f"sample={format_value['sample_format']}")
                if format_value.get("rate"):
                    fmt_parts.append(f"rate={format_value['rate']}")
                if format_value.get("channels"):
                    fmt_parts.append(f"channels={format_value['channels']}")
                if fmt_parts:
                    lines.append(f"    format: {', '.join(fmt_parts)}")
                channel_map = format_value.get("channel_map") or []
                if channel_map:
                    lines.append(f"    channel_map: {', '.join(channel_map)}")
        return lines

    def lines_for_highest_priority_sink(self, plugin: Plugin) -> list[str]:
        sink_id = self.run(plugin.get_highest_priority_sink_id())
        if sink_id is None:
            return ["Unable to determine a highest priority sink."]
        sinks = self.run(plugin.list_sinks()) or []
        entry = next((s for s in sinks if plugin._object_id_from_sink(s) == sink_id), None)
        lines = [f"Object ID: {sink_id}"]
        if entry:
            lines.append(f"Name: {entry.get('name')}")
            lines.append(f"Index: {plugin._sink_index_from_entry(entry)}")
            lines.append(f"Description: {entry.get('description')}")
            props = entry.get("properties") or {}
            priority = props.get("priority.session")
            if priority is not None:
                lines.append(f"priority.session: {priority}")
        return lines

    def lines_for_default_sink(self, plugin: Plugin) -> list[str]:
        sink_id = self.run(plugin.get_default_sink_id())
        if sink_id is None:
            return ["Unable to determine default sink."]
        sinks = self.run(plugin.list_sinks()) or []
        entry = next((s for s in sinks if plugin._object_id_from_sink(s) == sink_id), None)
        lines = [f"Object ID: {sink_id}"]
        if entry:
            lines.append(f"Name: {entry.get('name')}")
            lines.append(f"Index: {plugin._sink_index_from_entry(entry)}")
            lines.append(f"Description: {entry.get('description')}")
            props = entry.get("properties") or {}
            priority = props.get("priority.session")
        if priority is not None:
            lines.append(f"priority.session: {priority}")
        return lines

    @staticmethod
    def print_lines(lines: list[str]) -> None:
        for line in lines:
            print(line)


class CLIMenu:
    """Curses-driven CLI for interacting with Plugin helpers."""

    _curses_module = None

    @classmethod
    def _ensure_curses(cls):
        if cls._curses_module is None:
            import curses as curses_module
            cls._curses_module = curses_module
        return cls._curses_module

    def __init__(self, plugin: Plugin):
        self.plugin = plugin
        self.helper = CLIHelper()
        self.menu_items: list[tuple[str, Callable[[object], None]]] = [
            ("List sinks", self.list_sinks_action),
            ("List running apps (sink inputs)", self.list_sink_inputs_action),
            ("Get highest priority sink", self.highest_priority_sink_action),
            ("Get default sink", self.default_sink_action),
            ("Toggle app Virtual Surround Sound", self.toggle_app_virtual_surround_action),
            ("Toggle Virtual Surround Sound as default sink", self.toggle_default_surround_action),
            ("List HRIR files", self.list_hrir_files_action),
            ("Set HRIR file", self.set_hrir_file_action),
            ("List SOFA files", self.list_sofa_files_action),
            ("Set SOFA file", self.set_sofa_file_action),
            ("Run sound test", self.run_sound_test_action),
            ("Test random mixer profile", self.random_mixer_profile_action),
        ]

    @classmethod
    def _safe_curs_set(cls, mode: int):
        curses = cls._ensure_curses()
        try:
            curses.curs_set(mode)
        except curses.error:
            pass

    def _navigate_menu(self, stdscr, title: str, labels: list[str], footer: str) -> int | None:
        curses = self._ensure_curses()
        if not labels:
            return None
        index = 0
        offset = 0
        while True:
            stdscr.clear()
            height, width = stdscr.getmaxyx()
            self._safe_curs_set(0)
            visible_rows = max(1, height - 4)
            offset = max(0, min(offset, len(labels) - visible_rows))
            if index < offset:
                offset = index
            elif index >= offset + visible_rows:
                offset = index - visible_rows + 1
            stdscr.addnstr(0, 2, title, width - 4, curses.A_BOLD)
            for row in range(visible_rows):
                label_idx = offset + row
                if label_idx >= len(labels):
                    break
                prefix = f"{label_idx + 1}. {labels[label_idx]}"
                attr = curses.A_REVERSE if label_idx == index else curses.A_NORMAL
                stdscr.addnstr(2 + row, 2, prefix, width - 4, attr)
            stdscr.addnstr(height - 2, 2, footer, width - 4)
            stdscr.refresh()
            key = stdscr.getch()
            if key in (curses.KEY_UP, ord('k')):
                index = (index - 1) % len(labels)
            elif key in (curses.KEY_DOWN, ord('j')):
                index = (index + 1) % len(labels)
            elif key == curses.KEY_NPAGE:
                index = min(index + visible_rows, len(labels) - 1)
            elif key == curses.KEY_PPAGE:
                index = max(index - visible_rows, 0)
            elif key in (curses.KEY_ENTER, 10, 13):
                return index
            elif key in (27, ord('q'), ord('Q')):
                return None
            elif ord('0') <= key <= ord('9'):
                digit = key - ord('0')
                target = 9 if digit == 0 else digit - 1
                if target < len(labels):
                    index = target
                    return index

    def _show_scrollable_text(self, stdscr, title: str, lines: list[str], footer: str = "Press Enter to return"):
        curses = self._ensure_curses()
        content = lines or ["No data to display."]
        top = 0
        while True:
            stdscr.clear()
            height, width = stdscr.getmaxyx()
            self._safe_curs_set(0)
            visible_rows = max(1, height - 4)
            top = max(0, min(top, max(0, len(content) - visible_rows)))
            stdscr.addnstr(0, 2, title, width - 4, curses.A_BOLD)
            for row in range(visible_rows):
                line_idx = top + row
                if line_idx >= len(content):
                    break
                stdscr.addnstr(2 + row, 2, content[line_idx], width - 4)
            stdscr.addnstr(height - 2, 2, footer, width - 4)
            stdscr.refresh()
            key = stdscr.getch()
            if key in (curses.KEY_UP, ord('k')):
                top = max(0, top - 1)
            elif key in (curses.KEY_DOWN, ord('j')):
                if top + visible_rows < len(content):
                    top += 1
            elif key == curses.KEY_NPAGE:
                top = min(top + visible_rows, max(0, len(content) - visible_rows))
            elif key == curses.KEY_PPAGE:
                top = max(0, top - visible_rows)
            elif key in (curses.KEY_ENTER, 10, 13, 27, ord('q'), ord('Q')):
                return

    def _show_message(self, stdscr, title: str, message: str):
        self._show_scrollable_text(stdscr, title, [message])

    def list_sinks_action(self, stdscr):
        lines = self.helper.lines_for_sinks(self.plugin)
        self._show_scrollable_text(stdscr, "Available Sinks", lines)

    def list_sink_inputs_action(self, stdscr):
        lines = self.helper.lines_for_running_apps(self.plugin)
        self._show_scrollable_text(stdscr, "Running Apps (Sink Inputs)", lines)

    def highest_priority_sink_action(self, stdscr):
        lines = self.helper.lines_for_highest_priority_sink(self.plugin)
        self._show_scrollable_text(stdscr, "Highest Priority Sink", lines)

    def default_sink_action(self, stdscr):
        lines = self.helper.lines_for_default_sink(self.plugin)
        self._show_scrollable_text(stdscr, "Default Sink", lines)

    def toggle_app_virtual_surround_action(self, stdscr):
        sink_inputs = self.helper.run(self.plugin.list_sink_inputs())
        if not sink_inputs:
            self._show_message(stdscr, "Toggle App", "No running apps detected.")
            return
        grouped: dict[str, list[dict]] = {}
        canonical_for_name: dict[str, str] = {}
        for entry in sink_inputs:
            display_name = entry.get("name") or self.plugin._sink_input_app_name(entry) or f"Sink Input {entry.get('index')}"
            canonical_name = self.plugin._sink_input_app_name(entry) or display_name
            canonical_for_name.setdefault(display_name, canonical_name)
            grouped.setdefault(display_name, []).append(entry)
        enabled_apps = self.helper.run(self.plugin.get_enabled_apps_list()) or []
        app_names = sorted(grouped.keys())
        labels = []
        for name in app_names:
            canonical = canonical_for_name.get(name, name)
            status = "Enabled" if canonical in enabled_apps else "Disabled"
            labels.append(f"{name} [{status}] - {len(grouped[name])} stream(s)")
        selection = self._navigate_menu(
            stdscr,
            "Toggle Virtual Surround Sound for App",
            labels,
            "↑/↓ navigate • Enter toggle • q back"
        )
        if selection is None:
            return
        chosen = app_names[selection]
        canonical_chosen = canonical_for_name.get(chosen, chosen)
        if canonical_chosen in enabled_apps:
            self.helper.run(self.plugin.disable_for_app(canonical_chosen))
            self._show_message(stdscr, "Toggle App", f"'{chosen}' disabled for Virtual Surround Sound.")
        else:
            self.helper.run(self.plugin.enable_for_app(canonical_chosen))
            self._show_message(stdscr, "Toggle App", f"'{chosen}' enabled for Virtual Surround Sound.")

    def toggle_default_surround_action(self, stdscr):
        current = bool(self.helper.run(self.plugin.get_surround_sink_default()))
        if current:
            self.helper.run(self.plugin.disable_surround_sink_default())
            self._show_message(stdscr, "Default Sink Toggle", "Virtual Surround Sound is no longer the default sink.")
        else:
            self.helper.run(self.plugin.enable_surround_sink_default())
            self._show_message(stdscr, "Default Sink Toggle", "Virtual Surround Sound set as the default sink.")

    def list_hrir_files_action(self, stdscr):
        files = self.helper.run(self.plugin.get_hrir_file_list()) or []
        lines: list[str] = []
        if not files:
            lines.append("No HRIR files found.")
        else:
            for idx, entry in enumerate(files, start=1):
                channel_info = f"{entry.get('channel_count')} ch" if entry.get("channel_count") else "Unknown channels"
                lines.append(f"{idx}. {entry.get('label')} ({channel_info})")
                lines.append(f"    {entry.get('path')}")
        self._show_scrollable_text(stdscr, "HRIR Files", lines)

    def set_hrir_file_action(self, stdscr):
        files = self.helper.run(self.plugin.get_hrir_file_list()) or []
        if not files:
            self._show_message(stdscr, "Set HRIR File", "No HRIR files available.")
            return
        labels = []
        for entry in files:
            channel_info = f"{entry.get('channel_count')} ch" if entry.get("channel_count") else "?"
            labels.append(f"{entry.get('label')} ({channel_info})")
        selection = self._navigate_menu(
            stdscr,
            "Select HRIR File",
            labels,
            "↑/↓ navigate • Enter install • q cancel"
        )
        if selection is None:
            return
        selected = files[selection]
        path = selected.get("path")
        if not isinstance(path, str):
            self._show_message(stdscr, "Set HRIR File", "Invalid HRIR file entry.")
            return
        success = self.helper.run(self.plugin.set_hrir_file(path))
        if success:
            self.helper.run_delayed(lambda: self.plugin.check_state(), 5.0)
            self._show_message(
                stdscr,
                "Set HRIR File",
                f"Installed '{selected.get('label')}'.\nRechecking sink assignments shortly."
            )
        else:
            self._show_message(stdscr, "Set HRIR File", "Failed to install selected HRIR file.")

    def list_sofa_files_action(self, stdscr):
        files = self.helper.run(self.plugin.get_sofa_file_list()) or []
        lines: list[str] = []
        if not files:
            lines.append("No SOFA files found.")
        else:
            for idx, entry in enumerate(files, start=1):
                label = entry.get("label") or entry.get("path") or f"SOFA File {idx}"
                lines.append(f"{idx}. {label}")
                file_path = entry.get("path")
                if file_path:
                    lines.append(f"    {file_path}")
                size = entry.get("size")
                if isinstance(size, int):
                    lines.append(f"    size: {size} bytes")
        self._show_scrollable_text(stdscr, "SOFA Files", lines)

    def set_sofa_file_action(self, stdscr):
        files = self.helper.run(self.plugin.get_sofa_file_list()) or []
        if not files:
            self._show_message(stdscr, "Set SOFA File", "No SOFA files available.")
            return
        labels = []
        for entry in files:
            label = entry.get("label") or entry.get("path")
            labels.append(label or "SOFA file")
        selection = self._navigate_menu(
            stdscr,
            "Select SOFA File",
            labels,
            "↑/↓ navigate • Enter install • q cancel"
        )
        if selection is None:
            return
        selected = files[selection]
        path = selected.get("path")
        if not isinstance(path, str):
            self._show_message(stdscr, "Set SOFA File", "Invalid SOFA file entry.")
            return
        label_text = selected.get("label") or os.path.basename(path)
        success = self.helper.run(self.plugin.set_sofa_file(path))
        if success:
            self.helper.run_delayed(lambda: self.plugin.check_state(), 5.0)
            self._show_message(
                stdscr,
                "Set SOFA File",
                f"Installed '{label_text}'.\nRechecking sink assignments shortly."
            )
        else:
            self._show_message(stdscr, "Set SOFA File", "Failed to install selected SOFA file.")

    def run_sound_test_action(self, stdscr):
        sinks = self.helper.run(self.plugin.list_sinks())
        candidates = [s for s in sinks if isinstance(s.get("name"), str)]
        if not candidates:
            self._show_message(stdscr, "Sound Test", "No sinks available for testing.")
            return
        labels = []
        for sink in candidates:
            sink_index = self.plugin._sink_index_from_entry(sink)
            labels.append(f"{sink.get('name')} (index={sink_index if sink_index is not None else 'unknown'})")
        selection = self._navigate_menu(
            stdscr,
            "Select Sink for Sound Test",
            labels,
            "↑/↓ navigate • Enter run test • q cancel"
        )
        if selection is None:
            return
        sink_name = candidates[selection].get("name")
        if not isinstance(sink_name, str):
            self._show_message(stdscr, "Sound Test", "Invalid sink selection.")
            return
        self.helper.run(self.plugin.run_sound_test(sink_name))
        self._show_message(stdscr, "Sound Test", f"Started speaker-test on '{sink_name}'.")

    def random_mixer_profile_action(self, stdscr):
        channel_codes = ["FL", "FR", "FC", "LFE", "RL", "RR", "SL", "SR"]
        volumes = {code: random.randint(45, 120) for code in channel_codes}
        profile = {
            "name": "random",
            "usePerAppProfile": False,
            "volumes": volumes
        }
        success = self.helper.run(self.plugin.set_mixer_profile(profile))
        lines = [f"{code}: {value}%" for code, value in volumes.items()]
        if success:
            self._show_scrollable_text(stdscr, "Random Mixer Profile Applied", lines)
        else:
            self._show_scrollable_text(stdscr, "Random Mixer Profile Failed", lines + ["Operation failed."])

    def _main_menu(self, stdscr):
        self._safe_curs_set(0)
        labels = [label for label, _handler in self.menu_items]
        while True:
            selection = self._navigate_menu(
                stdscr,
                "Decky Virtual Surround Sound",
                labels + ["Exit"],
                "↑/↓ navigate • Enter select • q exit"
            )
            if selection is None or selection == len(labels):
                break
            _label, handler = self.menu_items[selection]
            handler(stdscr)

    def run(self):
        curses = self._ensure_curses()
        try:
            curses.wrapper(self._main_menu)
        finally:
            self.helper.close()


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description="Decky Virtual Surround Sound CLI")
    parser.add_argument("--menu", action="store_true", help="Launch the curses menu UI")
    parser.add_argument("--list-sinks", action="store_true", help="List available sinks")
    parser.add_argument("--list-running-apps", action="store_true", help="List sink inputs (running apps)")
    parser.add_argument("--print-highest-priority-sink", action="store_true", help="Print highest priority physical sink")
    parser.add_argument("--print-default-sink", action="store_true", help="Print current default sink")
    args = parser.parse_args()

    actions_requested = any([
        args.list_sinks,
        args.list_running_apps,
        args.print_highest_priority_sink,
        args.print_default_sink,
    ])

    if args.menu and actions_requested:
        parser.error("--menu cannot be combined with other options")

    if args.menu or not actions_requested:
        plugin = Plugin()
        menu = CLIMenu(plugin)
        menu.run()
        sys.exit(0)

    plugin = Plugin()
    helper = CLIHelper()
    exit_code = 0
    try:
        if args.list_sinks:
            lines = helper.lines_for_sinks(plugin)
            helper.print_lines(lines)
            if lines[:1] == ["No sinks found."]:
                exit_code |= 1
        if args.list_running_apps:
            lines = helper.lines_for_running_apps(plugin)
            helper.print_lines(lines)
            if lines[:1] == ["No running apps detected."]:
                exit_code |= 1
        if args.print_highest_priority_sink:
            lines = helper.lines_for_highest_priority_sink(plugin)
            helper.print_lines(lines)
            if lines[:1] == ["Unable to determine a highest priority sink."]:
                exit_code |= 1
        if args.print_default_sink:
            lines = helper.lines_for_default_sink(plugin)
            helper.print_lines(lines)
            if lines[:1] == ["Unable to determine default sink."]:
                exit_code |= 1
    finally:
        helper.close()
    sys.exit(exit_code)
