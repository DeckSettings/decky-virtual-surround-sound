#!/bin/bash
set -e

# Get script path
script_path="$(readlink -f "${BASH_SOURCE[0]}")"
script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
real_script_directory="$(cd "$(dirname "${script_path}")" && pwd)"

# Catch term signal
_term() {
    cleanup_virtual_surround_module
    cleanup_virtual_surround_default_sink
}

service_shutdown_requested="false"
_handle_signal() {
    if [[ "${service_shutdown_requested}" == "true" ]]; then
        return
    fi
    service_shutdown_requested="true"
    _term
    exit 1
}

mix_gain_db="-6dB"

# Configure pipewire module
virtual_surround_filter_sink_node="virtual-surround-sound-filter"
virtual_surround_filter_sink_name="input.virtual-surround-sound-filter"
virtual_surround_filter_sink_description="Virtual Surround Sound Filter"
if [[ -n "${VIRTUAL_SURROUND_SINK_SUFFIX:-}" ]]; then
    virtual_surround_filter_sink_name="virtual-surround-sound-${VIRTUAL_SURROUND_SINK_SUFFIX:-}"
    virtual_surround_filter_sink_description="Virtual Surround Sound (${VIRTUAL_SURROUND_SINK_SUFFIX:-})"
fi

virtual_surround_device_sink_node="virtual-surround-sound-input"
virtual_surround_device_sink_name="input.${virtual_surround_device_sink_node:?}"
virtual_surround_devoce_sink_description="Virtual Surround Sound"

# 7.1
device_module_args_8=$(
    cat <<EOF
{
    "audio.channels": 8,
    "audio.position": [ FL FR FC LFE RL RR SL SR ],
    "node.name": "${virtual_surround_device_sink_node:?}",
    "node.description": "${virtual_surround_devoce_sink_description:?}",
    filter.graph = {
        "nodes": [
            { "type": "builtin", "label": "copy", "name": "copyFL" },
            { "type": "builtin", "label": "copy", "name": "copyFR" },
            { "type": "builtin", "label": "copy", "name": "copyFC" },
            { "type": "builtin", "label": "copy", "name": "copyLFE" },
            { "type": "builtin", "label": "copy", "name": "copyRL" },
            { "type": "builtin", "label": "copy", "name": "copyRR" },
            { "type": "builtin", "label": "copy", "name": "copySL" },
            { "type": "builtin", "label": "copy", "name": "copySR" }
        ],
        "inputs":  [ "copyFL:In", "copyFR:In", "copyFC:In", "copyLFE:In", "copyRL:In", "copyRR:In", "copySL:In", "copySR:In" ],
        "outputs": [ "copyFL:Out", "copyFR:Out", "copyFC:Out", "copyLFE:Out", "copyRL:Out", "copyRR:Out", "copySL:Out", "copySR:Out" ]
    },
    capture.props = {
        "media.class": "Audio/Sink",
        "node.name": "${virtual_surround_device_sink_name:?}",
        "node.description": "${virtual_surround_devoce_sink_description:?}",
        "node.dont-fallback": true,
        "node.passive": true,
        "node.linger": true,
        "node.autoconnect": false,
        "stream.dont-remix": true,
        "channelmix.normalize": false,
        "audio.channels": 8,
        "audio.position": [ FL FR FC LFE RL RR SL SR ]
    },
    playback.props = {
        "node.passive": true,
        "node.autoconnect": false,
        "stream.dont-remix": true,
        "channelmix.normalize": false,
        "audio.channels": 8,
        "audio.position": [ FL FR FC LFE RL RR SL SR ]
    }
}
EOF
)
filter_module_convolver_args_8=$(
    cat <<EOF
{
    "audio.channels": 8,
    "audio.position": ["FL","FR","FC","LFE","RL","RR","SL","SR"],
    "node.name": "${virtual_surround_filter_sink_node:?}",
    "node.description": "${virtual_surround_filter_sink_description:?}",
    filter.graph = {
        "nodes": [
            { "type": "builtin", "label": "copy", "name": "copyFL" },
            { "type": "builtin", "label": "copy", "name": "copyFR" },
            { "type": "builtin", "label": "copy", "name": "copyFC" },
            { "type": "builtin", "label": "copy", "name": "copyRL" },
            { "type": "builtin", "label": "copy", "name": "copyRR" },
            { "type": "builtin", "label": "copy", "name": "copySL" },
            { "type": "builtin", "label": "copy", "name": "copySR" },
            { "type": "builtin", "label": "copy", "name": "copyLFE" },
            { "type": "builtin", "label": "convolver", "name": "convFL_L", "config": { "filename": "${HOME:?}/.config/pipewire/hrir.wav", "channel": 0 } },
            { "type": "builtin", "label": "convolver", "name": "convFL_R", "config": { "filename": "${HOME:?}/.config/pipewire/hrir.wav", "channel": 1 } },
            { "type": "builtin", "label": "convolver", "name": "convSL_L", "config": { "filename": "${HOME:?}/.config/pipewire/hrir.wav", "channel": 2 } },
            { "type": "builtin", "label": "convolver", "name": "convSL_R", "config": { "filename": "${HOME:?}/.config/pipewire/hrir.wav", "channel": 3 } },
            { "type": "builtin", "label": "convolver", "name": "convRL_L", "config": { "filename": "${HOME:?}/.config/pipewire/hrir.wav", "channel": 4 } },
            { "type": "builtin", "label": "convolver", "name": "convRL_R", "config": { "filename": "${HOME:?}/.config/pipewire/hrir.wav", "channel": 5 } },
            { "type": "builtin", "label": "convolver", "name": "convFC_L", "config": { "filename": "${HOME:?}/.config/pipewire/hrir.wav", "channel": 6 } },
            { "type": "builtin", "label": "convolver", "name": "convFR_R", "config": { "filename": "${HOME:?}/.config/pipewire/hrir.wav", "channel": 7 } },
            { "type": "builtin", "label": "convolver", "name": "convFR_L", "config": { "filename": "${HOME:?}/.config/pipewire/hrir.wav", "channel": 8 } },
            { "type": "builtin", "label": "convolver", "name": "convSR_R", "config": { "filename": "${HOME:?}/.config/pipewire/hrir.wav", "channel": 9 } },
            { "type": "builtin", "label": "convolver", "name": "convSR_L", "config": { "filename": "${HOME:?}/.config/pipewire/hrir.wav", "channel": 10 } },
            { "type": "builtin", "label": "convolver", "name": "convRR_R", "config": { "filename": "${HOME:?}/.config/pipewire/hrir.wav", "channel": 11 } },
            { "type": "builtin", "label": "convolver", "name": "convRR_L", "config": { "filename": "${HOME:?}/.config/pipewire/hrir.wav", "channel": 12 } },
            { "type": "builtin", "label": "convolver", "name": "convFC_R", "config": { "filename": "${HOME:?}/.config/pipewire/hrir.wav", "channel": 13 } },
            { "type": "builtin", "label": "convolver", "name": "convLFE_L", "config": { "filename": "${HOME:?}/.config/pipewire/hrir.wav", "channel": 6 } },
            { "type": "builtin", "label": "convolver", "name": "convLFE_R", "config": { "filename": "${HOME:?}/.config/pipewire/hrir.wav", "channel": 13 } },
            { "type": "builtin", "label": "mixer", "name": "mixL" },
            { "type": "builtin", "label": "mixer", "name": "mixR" }
        ],
        "links": [
            { "output": "copyFL:Out", "input": "convFL_L:In" },
            { "output": "copyFL:Out", "input": "convFL_R:In" },
            { "output": "copySL:Out", "input": "convSL_L:In" },
            { "output": "copySL:Out", "input": "convSL_R:In" },
            { "output": "copyRL:Out", "input": "convRL_L:In" },
            { "output": "copyRL:Out", "input": "convRL_R:In" },
            { "output": "copyFC:Out", "input": "convFC_L:In" },
            { "output": "copyFR:Out", "input": "convFR_R:In" },
            { "output": "copyFR:Out", "input": "convFR_L:In" },
            { "output": "copySR:Out", "input": "convSR_R:In" },
            { "output": "copySR:Out", "input": "convSR_L:In" },
            { "output": "copyRR:Out", "input": "convRR_R:In" },
            { "output": "copyRR:Out", "input": "convRR_L:In" },
            { "output": "copyFC:Out", "input": "convFC_R:In" },
            { "output": "copyLFE:Out", "input": "convLFE_L:In" },
            { "output": "copyLFE:Out", "input": "convLFE_R:In" },
            { "output": "convFL_L:Out", "input": "mixL:In 1", "gain": "${mix_gain_db:?}" },
            { "output": "convFL_R:Out", "input": "mixR:In 1", "gain": "${mix_gain_db:?}" },
            { "output": "convSL_L:Out", "input": "mixL:In 2", "gain": "${mix_gain_db:?}" },
            { "output": "convSL_R:Out", "input": "mixR:In 2", "gain": "${mix_gain_db:?}" },
            { "output": "convRL_L:Out", "input": "mixL:In 3", "gain": "${mix_gain_db:?}" },
            { "output": "convRL_R:Out", "input": "mixR:In 3", "gain": "${mix_gain_db:?}" },
            { "output": "convFC_L:Out", "input": "mixL:In 4", "gain": "${mix_gain_db:?}" },
            { "output": "convFC_R:Out", "input": "mixR:In 4", "gain": "${mix_gain_db:?}" },
            { "output": "convFR_R:Out", "input": "mixR:In 5", "gain": "${mix_gain_db:?}" },
            { "output": "convFR_L:Out", "input": "mixL:In 5", "gain": "${mix_gain_db:?}" },
            { "output": "convSR_R:Out", "input": "mixR:In 6", "gain": "${mix_gain_db:?}" },
            { "output": "convSR_L:Out", "input": "mixL:In 6", "gain": "${mix_gain_db:?}" },
            { "output": "convRR_R:Out", "input": "mixR:In 7", "gain": "${mix_gain_db:?}" },
            { "output": "convRR_L:Out", "input": "mixL:In 7", "gain": "${mix_gain_db:?}" },
            { "output": "convLFE_R:Out", "input": "mixR:In 8", "gain": "${mix_gain_db:?}" },
            { "output": "convLFE_L:Out", "input": "mixL:In 8", "gain": "${mix_gain_db:?}" }
        ],
        "inputs":  [ "copyFL:In", "copyFR:In", "copyFC:In", "copyLFE:In", "copyRL:In", "copyRR:In", "copySL:In", "copySR:In" ],
        "outputs": [ "mixL:Out", "mixR:Out" ]
    },
    capture.props = {
        "node.name": "input.${virtual_surround_filter_sink_node:?}",
        "node.description": "${virtual_surround_filter_sink_description:?}",
        "media.class": "Audio/Sink",
        "audio.channels": 8,
        "audio.position": [ FL FR FC LFE RL RR SL SR ],
        "node.dont-fallback": true,
        "node.linger": true,
        "node.autoconnect": false,
        "stream.dont-remix": true,
        "channelmix.normalize": false
    },
    playback.props = {
        "node.name": "output.${virtual_surround_filter_sink_node:?}",
        "node.passive": true,
        "node.autoconnect": false,
        "audio.channels": 2,
        "audio.position": [ FL FR ],
        "stream.dont-remix": true,
        "channelmix.normalize": false
    }
}
EOF
)
filter_module_sofa_args_8=$(
    cat <<EOF
{
    "audio.channels": 8,
    "audio.position": ["FL","FR","FC","LFE","RL","RR","SL","SR"],
    "node.name": "${virtual_surround_filter_sink_node:?}",
    "node.description": "${virtual_surround_filter_sink_description:?}",
    filter.graph = {
        "nodes": [
            {
                "type": "sofa",
                "label": "spatializer",
                "name": "spFL",
                "config": {
                    "filename": "${HOME:?}/.config/pipewire/hrir.sofa"
                },
                "control": {
                    "Azimuth": 30.0,
                    "Elevation": -10.0,
                    "Radius": 10.0
                }
            },
            {
                "type": "sofa",
                "label": "spatializer",
                "name": "spFR",
                "config": {
                    "filename": "${HOME:?}/.config/pipewire/hrir.sofa"
                },
                "control": {
                    "Azimuth": 330.0,
                    "Elevation": -10.0,
                    "Radius": 10.0
                }
            },
            {
                "type": "sofa",
                "label": "spatializer",
                "name": "spFC",
                "config": {
                    "filename": "${HOME:?}/.config/pipewire/hrir.sofa"
                },
                "control": {
                    "Azimuth": 0.0,
                    "Elevation": -10.0,
                    "Radius": 10.0
                }
            },
            {
                "type": "sofa",
                "label": "spatializer",
                "name": "spRL",
                "config": {
                    "filename": "${HOME:?}/.config/pipewire/hrir.sofa"
                },
                "control": {
                    "Azimuth": 150.0,
                    "Elevation": -10.0,
                    "Radius": 10.0
                }
            },
            {
                "type": "sofa",
                "label": "spatializer",
                "name": "spRR",
                "config": {
                    "filename": "${HOME:?}/.config/pipewire/hrir.sofa"
                },
                "control": {
                    "Azimuth": 210.0,
                    "Elevation": -10.0,
                    "Radius": 10.0
                }
            },
            {
                "type": "sofa",
                "label": "spatializer",
                "name": "spSL",
                "config": {
                    "filename": "${HOME:?}/.config/pipewire/hrir.sofa"
                },
                "control": {
                    "Azimuth": 90.0,
                    "Elevation": -10.0,
                    "Radius": 10.0
                }
            },
            {
                "type": "sofa",
                "label": "spatializer",
                "name": "spSR",
                "config": {
                    "filename": "${HOME:?}/.config/pipewire/hrir.sofa"
                },
                "control": {
                    "Azimuth": 270.0,
                    "Elevation": -10.0,
                    "Radius": 10.0
                }
            },
            {
                "type": "sofa",
                "label": "spatializer",
                "name": "spLFE",
                "config": {
                    "filename": "${HOME:?}/.config/pipewire/hrir.sofa"
                },
                "control": {
                    "Azimuth": 0.0,
                    "Elevation": -60.0,
                    "Radius": 3.0
                }
            },
            { "type": "builtin", "label": "mixer", "name": "mixL" },
            { "type": "builtin", "label": "mixer", "name": "mixR" }
        ],
        "links": [
            { "output": "spFL:Out L", "input": "mixL:In 1" },
            { "output": "spFL:Out R", "input": "mixR:In 1" },
            { "output": "spFR:Out L", "input": "mixL:In 2" },
            { "output": "spFR:Out R", "input": "mixR:In 2" },
            { "output": "spFC:Out L", "input": "mixL:In 3" },
            { "output": "spFC:Out R", "input": "mixR:In 3" },
            { "output": "spRL:Out L", "input": "mixL:In 4" },
            { "output": "spRL:Out R", "input": "mixR:In 4" },
            { "output": "spRR:Out L", "input": "mixL:In 5" },
            { "output": "spRR:Out R", "input": "mixR:In 5" },
            { "output": "spSL:Out L", "input": "mixL:In 6" },
            { "output": "spSL:Out R", "input": "mixR:In 6" },
            { "output": "spSR:Out L", "input": "mixL:In 7" },
            { "output": "spSR:Out R", "input": "mixR:In 7" },
            { "output": "spLFE:Out L", "input": "mixL:In 8" },
            { "output": "spLFE:Out R", "input": "mixR:In 8" }
        ],
        "inputs":  [ "spFL:In", "spFR:In", "spFC:In", "spLFE:In", "spRL:In", "spRR:In", "spSL:In", "spSR:In" ],
        "outputs": [ "mixL:Out", "mixR:Out" ]
    },
    capture.props = {
        "node.name": "input.${virtual_surround_filter_sink_node:?}",
        "media.class": "Audio/Sink",
        "audio.channels": 8,
        "audio.position": [ FL FR FC LFE RL RR SL SR ],
        "node.dont-fallback": true,
        "node.linger": true,
        "node.autoconnect": false,
        "stream.dont-remix": true,
        "channelmix.normalize": false
    },
    playback.props = {
        "node.name": "output.${virtual_surround_filter_sink_node:?}",
        "node.passive": true,
        "node.autoconnect": false,
        "audio.channels": 2,
        "audio.position": [ FL FR ],
        "stream.dont-remix": true,
        "channelmix.normalize": false
    }
}
EOF
)
# Check channel counthrir.wav files with command:
#   > ffprobe -v error -select_streams a:0 -show_entries stream=channels -of default=noprint_wrappers=1:nokey=1 /home/deck/.config/pipewire/hrir.wav
# Or get all info
#   ffprobe -v error -print_format json -show_format -show_streams /home/deck/.config/pipewire/hrir.wav

# Add the DBUS_SESSION_BUS_ADDRESS environment variable
if [[ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ]]; then
    eval $(dbus-launch --sh-syntax)
    export DBUS_SESSION_BUS_ADDRESS
fi

# Configure systemd service
if [ -z "${XDG_RUNTIME_DIR:-}" ]; then
    export XDG_RUNTIME_DIR="/run/user/$(id -u)"
fi
filter_module_pid_file="${XDG_RUNTIME_DIR:?}/${virtual_surround_filter_sink_node:?}.pid"
device_module_pid_file="${XDG_RUNTIME_DIR:?}/${virtual_surround_device_sink_node:?}.pid"
service_name="virtual-surround-sound.service"
service_file="${HOME:?}/.config/systemd/user/${service_name:?}"
run_script="${HOME:?}/.config/pipewire/run.sh"
service_config=$(
    cat <<EOF
[Unit]
Description=${virtual_surround_filter_sink_description:?}
Requires=pipewire.service
After=pipewire.service
PartOf=pipewire.service wireplumber.service

[Service]
Type=simple
Restart=always
RestartSec=1
StartLimitInterval=5
StartLimitBurst=5
ExecStart=${run_script:?}

[Install]
WantedBy=default.target
EOF
)

get_run_script_contents() {
    local filter_type="${1:-convolver}"
    cat <<EOF
#!/bin/bash
set -euo pipefail

cleanup() {
    echo "Missing service script at '${script_directory:?}/service.sh'. Cleaning up systemd unit: ${service_name}"
    systemctl --user disable "${service_name}" >/dev/null 2>&1 || true
    rm -f "${service_file}" >/dev/null 2>&1 || true
    systemctl --user daemon-reload >/dev/null 2>&1 || true
    rm -f "${run_script:?}" >/dev/null 2>&1 || true
}

echo "Checking for service script..."
if [[ ! -f "${script_directory:?}/service.sh" ]]; then
    cleanup
    exit 0
fi

exec "${script_directory:?}/service.sh" run --filter=${filter_type:?}
EOF
}

virtual_surround_filter_sink_pw_cli_pid=""
virtual_surround_device_sink_pw_cli_pid=""

reset_default_sink() {
    local default_id=""
    default_id=$(wpctl status | awk '/\*/ && /Audio\/Sink/ {if (match($0,/[0-9]+\./,m)) {print substr(m[0], 1, length(m[0])-1); exit}}')
    if [[ -n "${default_id}" ]]; then
        wpctl set-default "${default_id}" >/dev/null 2>&1 || true
        wpctl clear-default
    fi
}

cleanup_virtual_surround_module() {
    local running_pid=""
    local terminated=""
    if [[ -n "${virtual_surround_filter_sink_pw_cli_pid:-}" ]]; then
        running_pid="${virtual_surround_filter_sink_pw_cli_pid}"
    elif [[ -f "${filter_module_pid_file:?}" ]]; then
        running_pid=$(cat "${filter_module_pid_file:?}" 2>/dev/null || true)
    fi

    if [[ -n "${running_pid}" ]]; then
        kill -TERM "${running_pid}" >/dev/null 2>&1 || true
        terminated="true"
    fi
    if [[ -f "${filter_module_pid_file:?}" ]]; then
        rm -f "${filter_module_pid_file:?}" >/dev/null 2>&1 || true
    fi
    if [[ "${terminated}" == "true" ]]; then
        sleep 0.2
    fi
    virtual_surround_filter_sink_pw_cli_pid=""
}

create_virtual_surround_module() {
    local filter_type="${1:-convolver}"
    local channel_count="8"
    local module_args="${filter_module_convolver_args_8}"
    if [[ "${filter_type}" == "sofa" ]]; then
        module_args="${filter_module_sofa_args_8}"
    fi

    cleanup_virtual_surround_module

    echo "Creating and loading module libpipewire-module-filter-chain (${filter_type:?}) with ${channel_count:?} channels - ${virtual_surround_filter_sink_name:?}"
    pw-cli -m load-module libpipewire-module-filter-chain "${module_args:?}" &
    virtual_surround_filter_sink_pw_cli_pid=$!
    echo "${virtual_surround_filter_sink_pw_cli_pid:?}" >"${filter_module_pid_file:?}"
    sleep 1 # <- sleep for a second to ensure everything is loaded before linking

    if ! wait_for_sink_registration "${virtual_surround_filter_sink_name:?}" 40 0.25; then
        echo "ERROR! Unable to detect sink '${virtual_surround_filter_sink_name:?}' after loading module."
        cleanup_virtual_surround_module
        return 1
    fi

    echo "Created filter-chain sink '${virtual_surround_filter_sink_name:?}' (pid ${virtual_surround_filter_sink_pw_cli_pid:?})"
    return 0
}

cleanup_virtual_surround_default_sink() {
    local running_pid=""
    local terminated=""
    if [[ -n "${virtual_surround_device_sink_pw_cli_pid:-}" ]]; then
        running_pid="${virtual_surround_device_sink_pw_cli_pid}"
    elif [[ -f "${device_module_pid_file:?}" ]]; then
        running_pid=$(cat "${device_module_pid_file:?}" 2>/dev/null || true)
    fi

    if [[ -n "${running_pid}" ]]; then
        kill -TERM "${running_pid}" >/dev/null 2>&1 || true
        terminated="true"
    fi
    if [[ -f "${device_module_pid_file:?}" ]]; then
        rm -f "${device_module_pid_file:?}" >/dev/null 2>&1 || true
    fi
    if [[ "${terminated}" == "true" ]]; then
        sleep 0.2
    fi
    virtual_surround_device_sink_pw_cli_pid=""
}

create_virtual_surround_default_sink() {
    local channel_count="${1:-8}"
    local module_args="${device_module_args_8}"

    cleanup_virtual_surround_default_sink

    echo "Creating and loading module libpipewire-module-filter-chain with ${channel_count:?} channels - ${virtual_surround_device_sink_name:?}"
    pw-cli -m load-module libpipewire-module-filter-chain "${module_args:?}" &
    virtual_surround_device_sink_pw_cli_pid=$!
    echo "${virtual_surround_device_sink_pw_cli_pid:?}" >"${device_module_pid_file:?}"
    sleep 1 # <- sleep for a second to ensure everything is loaded before linking

    if ! wait_for_sink_registration "${virtual_surround_device_sink_name:?}" 40 0.25; then
        echo "ERROR! Unable to detect sink '${virtual_surround_device_sink_name:?}' after loading module."
        cleanup_virtual_surround_default_sink
        return 1
    fi

    echo "Created filter-chain sink '${virtual_surround_device_sink_name:?}' (pid ${virtual_surround_device_sink_pw_cli_pid:?})"
    return 0
}

link_ports() {
    local output_port="$1"
    local input_port="$2"
    local result
    local existing_inputs
    existing_inputs=$(pw-link -l 2>/dev/null | awk -v target="${output_port}" '
        BEGIN {record = 0}
        {
            line = $0
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
            if (line == target) {
                record = 1
                next
            }
            if (record) {
                if (line ~ /^\|[-<]>/) {
                    sub(/^\|[-<]>[[:space:]]*/, "", line)
                    print line
                    next
                }
                if (line !~ /^\|/) {
                    record = 0
                }
            }
        }
    ')
    for existing in ${existing_inputs}; do
        if [[ -n "${existing}" && "${existing}" != "${input_port}" ]]; then
            pw-link -d "${output_port}" "${existing}" >/dev/null 2>&1 || true
        fi
    done
    if result=$(pw-link -w "${output_port}" "${input_port}" 2>&1); then
        echo "Linking ${output_port} -> ${input_port}"
        return 0
    fi
    if printf '%s\n' "${result}" | grep -qi 'file exists'; then
        return 0
    fi
    echo "Failed to link ${output_port} -> ${input_port}: ${result}"
    return 1
}

link_virtual_surround_chain() {
    local channel_count="${1:-8}"
    local -a channels=(FL FR FC LFE RL RR SL SR)

    local device_node="${virtual_surround_device_sink_node}"
    local filter_node="${virtual_surround_filter_sink_node}"
    device_node="${device_node#input.}"
    device_node="${device_node#output.}"
    filter_node="${filter_node#input.}"
    filter_node="${filter_node#output.}"
    local default_output_prefix="output.${device_node}:output_"
    local surround_input_prefix="input.${filter_node}:playback_"
    local surround_output_prefix="output.${filter_node}:output_"

    local default_sink_name
    default_sink_name=$(wpctl status | awk '/\*/ && /Audio\/Sink/ { sub(/.*\*\s*[0-9]+\.\s*/, ""); sub(/\s*\[.*/, ""); print; exit }' | sed 's/[[:space:]]*$//')
    local virtual_filter="${virtual_surround_filter_sink_name:?}"
    local virtual_device="${virtual_surround_device_sink_name:?}"

    if [[ -n "${default_sink_name}" && ("${default_sink_name}" == "${virtual_filter}" || "${default_sink_name}" == "${virtual_device}") ]]; then
        if ! command -v python3 >/dev/null 2>&1; then
            echo "Unable to find python to determine the highest priority sink."
            return 1
        fi
        local fallback_output=""
        pushd "${script_directory:?}" >/dev/null
        fallback_output=$(python3 ./main.py --print-highest-priority-sink 2>/dev/null || true)
        popd >/dev/null
        local fallback_object_name
        fallback_object_name=$(printf "%s\n" "${fallback_output}" | awk -F': ' '/^Name:/ {print $2; exit}')
        if [[ -z "${fallback_object_name:-}" ]]; then
            echo "Unable to determine fallback sink name."
            return 1
        fi
        default_sink_name="${fallback_object_name:?}"
        #local fallback_object_id
        #fallback_object_id=$(printf "%s\n" "${fallback_output}" | awk -F': ' '/^Object ID:/ {print $2; exit}')
        #if [[ -z "${fallback_object_id}" ]]; then
        #    echo "Unable to determine fallback sink object ID."
        #    return 1
        #fi
        #echo "Default sink is virtual; switching to highest priority sink object ${fallback_object_id}"
        #wpctl set-default "${fallback_object_id}" >/dev/null 2>&1 || true
        #default_sink_name=$(wpctl status | awk '/\*/ && /Audio\/Sink/ { sub(/.*\*\s*[0-9]+\.\s*/, ""); sub(/\s*\[.*/, ""); print; exit }' | sed 's/[[:space:]]*$//')
    fi

    if [[ -z "${default_sink_name}" || "${default_sink_name}" == "${virtual_filter}" || "${default_sink_name}" == "${virtual_device}" ]]; then
        echo "Unable to detect a valid target output sink"
        return 1
    fi

    local output_ports
    local input_ports
    output_ports=$(pw-link -o 2>/dev/null | sed 's/[[:space:]]*$//')
    input_ports=$(pw-link -i 2>/dev/null | sed 's/[[:space:]]*$//')

    for ch in "${channels[@]}"; do
        local device_output_port="${default_output_prefix}${ch}"
        local surround_input_port="${surround_input_prefix}${ch}"

        if ! grep -Fxq -- "${device_output_port}" <<<"${output_ports}"; then
            echo "Skipping ${device_output_port} -> ${surround_input_port}: device output port missing"
            continue
        fi
        if ! grep -Fxq -- "${surround_input_port}" <<<"${input_ports}"; then
            echo "Skipping ${device_output_port} -> ${surround_input_port}: filter input port missing"
            continue
        fi

        if ! link_ports "${device_output_port}" "${surround_input_port}"; then
            return 1
        fi
    done

    local target_input_prefix="${default_sink_name}:playback_"
    local target_channels=(FL FR)
    for ch in "${target_channels[@]}"; do
        local surround_output_port="${surround_output_prefix}${ch}"
        local target_input_port="${target_input_prefix}${ch}"

        if ! grep -Fxq -- "${surround_output_port}" <<<"${output_ports}"; then
            echo "Skipping ${surround_output_port} -> ${target_input_port}: filter output port missing"
            continue
        fi
        if ! grep -Fxq -- "${target_input_port}" <<<"${input_ports}"; then
            echo "Skipping ${surround_output_port} -> ${target_input_port}: target sink input port missing"
            continue
        fi
        if ! link_ports "${surround_output_port}" "${target_input_port}"; then
            echo "Failed"
            return 1
        fi
    done
    return 0
}

wait_for_sink_registration() {
    local sink_name="$1"
    local retries="${2:-30}"
    local delay_seconds="${3:-0.25}"
    local i
    for ((i = 0; i < retries; i++)); do
        if pactl list short sinks | cut -f2 | grep -Fxq -- "${sink_name:?}"; then
            return 0
        fi
        sleep "${delay_seconds}"
    done
    return 1
}

virtual_surround_sinks_exist() {
    local sink_list
    if ! sink_list=$(pactl list short sinks 2>/dev/null | cut -f2); then
        return 1
    fi

    if ! grep -Fxq -- "${virtual_surround_filter_sink_name:?}" <<<"${sink_list}"; then
        return 1
    fi

    if ! grep -Fxq -- "${virtual_surround_device_sink_name:?}" <<<"${sink_list}"; then
        return 1
    fi

    return 0
}

kill_all_running_instances() {
    cleanup_virtual_surround_module
    cleanup_virtual_surround_default_sink
    running_pids=$(ps aux | grep -i "pw-cli -m load-module" | grep -v grep | grep "${virtual_surround_filter_sink_node:?}" | awk '{print $2}')
    if [ -n "${running_pids}" ]; then
        kill -TERM ${running_pids}
    fi
}

is_pid_running() {
    local pid="$1"
    [[ -n "${pid}" ]] && kill -0 "${pid}" >/dev/null 2>&1
}

run() {
    trap '_handle_signal' INT QUIT HUP TERM ERR
    echo "Running service"
    local filter_type="convolver"
    while [[ $# -gt 0 ]]; do
        case "$1" in
        --filter=*)
            filter_type="${1#*=}"
            ;;
        --filter)
            shift
            filter_type="$1"
            ;;
        *)
            echo "Invalid arg: $1"
            print_usage_and_exit 1
            ;;
        esac
        shift
    done

    if [[ "${filter_type}" != "convolver" && "${filter_type}" != "sofa" ]]; then
        echo "Invalid filter value: ${filter_type}. Must be convolver or sofa."
        exit 1
    fi

    local channels="8"

    reset_default_sink

    if ! create_virtual_surround_module "${filter_type:?}"; then
        _term
        exit 1
    fi

    if ! create_virtual_surround_default_sink "${channels:?}"; then
        _term
        exit 1
    fi

    local linking_failed=0
    while true; do
        sleep 1
        if ! is_pid_running "${virtual_surround_filter_sink_pw_cli_pid}" || ! is_pid_running "${virtual_surround_device_sink_pw_cli_pid}"; then
            break
        fi
        if ! virtual_surround_sinks_exist; then
            echo "Virtual surround sinks are no longer available"
            linking_failed=1
            break
        fi
        if ! link_virtual_surround_chain "${channels:?}"; then
            linking_failed=1
            break
        fi
    done

    cleanup_virtual_surround_default_sink
    cleanup_virtual_surround_module

    if [[ "${linking_failed}" -ne 0 ]]; then
        echo "Failed to rewire virtual surround nodes"
        exit 1
    fi

    echo "DONE"
}

speaker_test() {
    echo "Running sound test"
    local pulse_sink_name="${virtual_surround_filter_sink_name:?}"
    while [[ $# -gt 0 ]]; do
        case "$1" in
        --sink=*)
            pulse_sink_name="${1#*=}"
            ;;
        --sink)
            shift
            pulse_sink_name="$1"
            ;;
        *)
            echo "Invalid arg: $1"
            print_usage_and_exit 1
            ;;
        esac
        shift
    done

    for i in {0..6}; do
        speaker-test -D "pulse:${pulse_sink_name:?}" -c 8 -t wave -s $((i + 1))
    done
    speaker-test -D "pulse:${pulse_sink_name:?}" -c 8 -t sine -f 50 -s 8
}

install_service() {
    echo "Installing service: ${service_name:?}"
    local install_filter_type="convolver"
    local restart_after_install="false"
    while [[ $# -gt 0 ]]; do
        case "$1" in
        --restart-after-install)
            restart_after_install="true"
            ;;
        --filter=*)
            install_filter_type="${1#*=}"
            ;;
        --filter)
            shift
            install_filter_type="$1"
            ;;
        *)
            echo "Invalid arg: $1"
            print_usage_and_exit 1
            ;;
        esac
        shift
    done
    if [[ "${install_filter_type}" != "convolver" && "${install_filter_type}" != "sofa" ]]; then
        echo "Invalid filter value: ${install_filter_type}. Must be convolver or sofa."
        exit 1
    fi
    local run_script_contents
    run_script_contents=$(get_run_script_contents "${install_filter_type:?}")
    echo "  - Creating directory: '${HOME:?}/.config/pipewire'"
    mkdir -p "${HOME:?}/.config/pipewire"
    echo "  - Ensure directory and all contents is RW by the user"
    chmod 755 "${HOME:?}/.config/pipewire"
    chmod u+rw -R "${HOME:?}/.config/pipewire"
    echo "  - Installing run wrapper script: ${run_script:?}"
    echo "${run_script_contents:?}" >"${run_script:?}"
    chmod +x "${run_script:?}"
    echo "  - Installing systemd unit: ${service_file:?}"
    echo "${service_config:?}" >"${service_file:?}"
    echo "  - Exec daemon-reload"
    systemctl --user daemon-reload
    echo "  - Enabling systemd unit"
    systemctl --user enable --now "${service_name:?}"
    local start_cmd="start"
    if [[ "${restart_after_install:-}" == "true" ]]; then
        start_cmd="restart"
    fi
    echo "  - Now ${start_cmd:?}ing systemd service"
    systemctl --user ${start_cmd:?} "${service_name:?}"
    echo "Systemd service installed and ${start_cmd:?}ed."
}

uninstall_service() {
    echo "Uninstalling systemd unit: ${service_name:?}"
    if [ -f "${service_file:?}" ]; then
        # Stop and disable the service
        echo "  - Stopping systemd service"
        systemctl --user stop "${service_name}"
        echo "  - Disabling systemd unit"
        systemctl --user disable "${service_name}"
        # Remove the service file
        echo "  - Removing systemd unit: ${service_file:?}"
        rm -f "${service_file}"
        echo "  - Exec daemon-reload"
        systemctl --user daemon-reload
        echo "  - Removing run wrapper script: ${run_script:?}"
        rm -f "${run_script:?}"
        echo "Systemd service stopped and uninstalled."
    else
        echo "Systemd service has not been installed. Run this script with the 'install' command to install it."
    fi
}

restart_service() {
    echo "Restarting systemd unit: ${service_name:?}"
    if [ -f "${service_file:?}" ]; then
        echo "  - Restarting systemd service"
        systemctl --user restart "${service_name:?}"
        echo "Systemd service restarted."
    else
        echo "Systemd service has not been installed. Run this script with the 'install' command to install it."
    fi
}

stop_service() {
    echo "Stopping running service: ${service_name:?}"
    if [ -f "${service_file:?}" ]; then
        echo "  - Stopping systemd service"
        systemctl --user stop "${service_name:?}"
        echo "Systemd service stopped."
    else
        echo "Systemd service has not been installed. Run this script with the 'install' command to install it."
    fi
}

print_usage_and_exit() {
    echo "Usage: $0 {run|install|uninstall|restart|stop|kill-all} [--filter=<convolver|sofa>] [additional args...]"
    exit "$1"
}

# Check if the effective user ID is 0 (root)
if [ "$EUID" -eq 0 ]; then
    echo "Error: This script must not be run as root. This is bad. You should be running this as a standard user." >&2
    exit 1
fi

# Parse command line arguments
if [[ $# -eq 0 ]]; then
    print_usage_and_exit 1
fi

# The first parameter is the command.
cmd="$1"
shift

case "$cmd" in
"run")
    run "$@"
    ;;
"speaker-test")
    speaker_test "$@"
    ;;
"install")
    install_service "$@"
    ;;
"uninstall")
    uninstall_service "$@"
    ;;
"restart")
    restart_service "$@"
    ;;
"stop")
    stop_service "$@"
    ;;
"kill-all")
    kill_all_running_instances "$@"
    ;;
*)
    echo "Invalid command: $cmd"
    print_usage_and_exit 1
    ;;
esac
