#!/bin/bash
set -e

# Get script path
script_directory=$(cd $(dirname ${BASH_SOURCE[@]}) && pwd)

# Catch term signal
_term() {
    kill -TERM "$pw_cli_pid" 2>/dev/null
}
trap '_term' INT QUIT HUP TERM ERR

# Configure pipewire module
module_name="libpipewire-module-filter-chain"
virtual_surround_sink_name="virtual-surround-sound"
virtual_surround_sink_description="Virtual Surround Sound"
if [[ -n "${VIRTUAL_SURROUND_SINK_SUFFIX:-}" ]]; then
    virtual_surround_sink_name="virtual-surround-sound-${VIRTUAL_SURROUND_SINK_SUFFIX:-}"
    virtual_surround_sink_description="Virtual Surround Sound (${VIRTUAL_SURROUND_SINK_SUFFIX:-})"
fi
virtual_sink_name="virtual-sink"
# 2
dummy_virtual_sink_2=$(
    cat <<EOF
context.modules = [
    { 
        name = "libpipewire-module-filter-chain"
        args = {
            node.name = "virtual-sink"
            node.description = "Virtual Sink"
            media.name = "Virtual Sink"
            filter.graph = {
                nodes = [
                    {
                        name   = copyIL
                        type   = builtin
                        label  = copy
                    }
                    {
                        name   = copyOL
                        type   = builtin
                        label  = copy
                    }
                    {
                        name   = copyIR
                        type   = builtin
                        label  = copy
                    }
                    {
                        name   = copyOR
                        type   = builtin
                        label  = copy
                    }
                ]
                links = [
                    { output = "copyIL:Out" input = "copyOL:In" }
                    { output = "copyIR:Out" input = "copyOR:In" }
                ]
                inputs  = [ "copyIL:In" "copyIR:In" ]
                outputs = [ "copyOL:Out" "copyOR:Out" ]
            }
            capture.props = {
                node.name         = "input.virtual-sink"
                media.class       = Audio/Sink
                audio.channels    = 2
                audio.position    = [ FL FR ]
            }
            playback.props = {
                node.name         = "output.virtual-sink"
                node.passive      = true
                audio.channels    = 2
                audio.position    = [ FL FR ]
            }
        }
    }
]
EOF
)

mix_gain_db="-6dB"
hrir_fl_left=0
hrir_fl_right=1
hrir_fr_left=8
hrir_fr_right=7
hrir_fc_left=6
hrir_fc_right=13
hrir_rl_left=4
hrir_rl_right=5
hrir_rr_left=12
hrir_rr_right=11
hrir_sl_left=2
hrir_sl_right=3
hrir_sr_left=10
hrir_sr_right=9

# 7.1
args_8='{
    "audio.channels": 8,
    "audio.position": ["FL","FR","FC","LFE","RL","RR","SL","SR"],
    "node.name": "'${virtual_surround_sink_name:?}'",
    "node.description": "'${virtual_surround_sink_description:?}'",
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
            { "type": "builtin", "label": "convolver", "name": "convFL_L", "config": { "filename": "'${HOME:?}'/.config/pipewire/hrir.wav", "channel": '${hrir_fl_left:?}' } },
            { "type": "builtin", "label": "convolver", "name": "convFL_R", "config": { "filename": "'${HOME:?}'/.config/pipewire/hrir.wav", "channel": '${hrir_fl_right:?}' } },
            { "type": "builtin", "label": "convolver", "name": "convSL_L", "config": { "filename": "'${HOME:?}'/.config/pipewire/hrir.wav", "channel": '${hrir_sl_left:?}' } },
            { "type": "builtin", "label": "convolver", "name": "convSL_R", "config": { "filename": "'${HOME:?}'/.config/pipewire/hrir.wav", "channel": '${hrir_sl_right:?}' } },
            { "type": "builtin", "label": "convolver", "name": "convRL_L", "config": { "filename": "'${HOME:?}'/.config/pipewire/hrir.wav", "channel": '${hrir_rl_left:?}' } },
            { "type": "builtin", "label": "convolver", "name": "convRL_R", "config": { "filename": "'${HOME:?}'/.config/pipewire/hrir.wav", "channel": '${hrir_rl_right:?}' } },
            { "type": "builtin", "label": "convolver", "name": "convFC_L", "config": { "filename": "'${HOME:?}'/.config/pipewire/hrir.wav", "channel": '${hrir_fc_left:?}' } },
            { "type": "builtin", "label": "convolver", "name": "convFR_R", "config": { "filename": "'${HOME:?}'/.config/pipewire/hrir.wav", "channel": '${hrir_fr_right:?}' } },
            { "type": "builtin", "label": "convolver", "name": "convFR_L", "config": { "filename": "'${HOME:?}'/.config/pipewire/hrir.wav", "channel": '${hrir_fr_left:?}' } },
            { "type": "builtin", "label": "convolver", "name": "convSR_R", "config": { "filename": "'${HOME:?}'/.config/pipewire/hrir.wav", "channel": '${hrir_sr_right:?}' } },
            { "type": "builtin", "label": "convolver", "name": "convSR_L", "config": { "filename": "'${HOME:?}'/.config/pipewire/hrir.wav", "channel": '${hrir_sr_left:?}' } },
            { "type": "builtin", "label": "convolver", "name": "convRR_R", "config": { "filename": "'${HOME:?}'/.config/pipewire/hrir.wav", "channel": '${hrir_rr_right:?}' } },
            { "type": "builtin", "label": "convolver", "name": "convRR_L", "config": { "filename": "'${HOME:?}'/.config/pipewire/hrir.wav", "channel": '${hrir_rr_left:?}' } },
            { "type": "builtin", "label": "convolver", "name": "convFC_R", "config": { "filename": "'${HOME:?}'/.config/pipewire/hrir.wav", "channel": '${hrir_fc_right:?}' } },
            { "type": "builtin", "label": "convolver", "name": "convLFE_L", "config": { "filename": "'${HOME:?}'/.config/pipewire/hrir.wav", "channel": '${hrir_fc_left:?}' } },
            { "type": "builtin", "label": "convolver", "name": "convLFE_R", "config": { "filename": "'${HOME:?}'/.config/pipewire/hrir.wav", "channel": '${hrir_fc_right:?}' } },
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
            { "output": "convFL_L:Out", "input": "mixL:In 1", "gain": "'${mix_gain_db:?}'" },
            { "output": "convFL_R:Out", "input": "mixR:In 1", "gain": "'${mix_gain_db:?}'" },
            { "output": "convSL_L:Out", "input": "mixL:In 2", "gain": "'${mix_gain_db:?}'" },
            { "output": "convSL_R:Out", "input": "mixR:In 2", "gain": "'${mix_gain_db:?}'" },
            { "output": "convRL_L:Out", "input": "mixL:In 3", "gain": "'${mix_gain_db:?}'" },
            { "output": "convRL_R:Out", "input": "mixR:In 3", "gain": "'${mix_gain_db:?}'" },
            { "output": "convFC_L:Out", "input": "mixL:In 4", "gain": "'${mix_gain_db:?}'" },
            { "output": "convFC_R:Out", "input": "mixR:In 4", "gain": "'${mix_gain_db:?}'" },
            { "output": "convFR_R:Out", "input": "mixR:In 5", "gain": "'${mix_gain_db:?}'" },
            { "output": "convFR_L:Out", "input": "mixL:In 5", "gain": "'${mix_gain_db:?}'" },
            { "output": "convSR_R:Out", "input": "mixR:In 6", "gain": "'${mix_gain_db:?}'" },
            { "output": "convSR_L:Out", "input": "mixL:In 6", "gain": "'${mix_gain_db:?}'" },
            { "output": "convRR_R:Out", "input": "mixR:In 7", "gain": "'${mix_gain_db:?}'" },
            { "output": "convRR_L:Out", "input": "mixL:In 7", "gain": "'${mix_gain_db:?}'" },
            { "output": "convLFE_R:Out", "input": "mixR:In 8", "gain": "'${mix_gain_db:?}'" },
            { "output": "convLFE_L:Out", "input": "mixL:In 8", "gain": "'${mix_gain_db:?}'" }
        ],
        "inputs":  [ "copyFL:In", "copyFR:In", "copyFC:In", "copyLFE:In", "copyRL:In", "copyRR:In", "copySL:In", "copySR:In" ],
        "outputs": [ "mixL:Out", "mixR:Out" ]
    },
    capture.props = {
        "media.class": "Audio/Sink",
        "audio.channels": 8,
        "audio.position": [ FL FR FC LFE RL RR SL SR ],
        "node.dont-fallback": true,
        "node.linger": true,
        "stream.dont-remix": true,
        "channelmix.normalize": false
    },
    playback.props = {
        "node.passive": true,
        "audio.channels": 2,
        "audio.position": [ FL FR ],
        "stream.dont-remix": true,
        "channelmix.normalize": false
    }
}'
# 5.1
args_6='{
    "audio.channels": 6,
    "audio.position": ["FL","FR","FC","LFE","SL","SR"],
    "node.name": "'${virtual_surround_sink_name:?}'",
    "node.description": "'${virtual_surround_sink_description:?}'",
    filter.graph = {
        "nodes": [
            { "type": "builtin", "label": "convolver", "name": "convFL_L", "config": { "filename": "'${HOME:?}'/.config/pipewire/hrir.wav", "channel": 0 } },
            { "type": "builtin", "label": "convolver", "name": "convFL_R", "config": { "filename": "'${HOME:?}'/.config/pipewire/hrir.wav", "channel": 1 } },
            { "type": "builtin", "label": "convolver", "name": "convFR_L", "config": { "filename": "'${HOME:?}'/.config/pipewire/hrir.wav", "channel": 1 } },
            { "type": "builtin", "label": "convolver", "name": "convFR_R", "config": { "filename": "'${HOME:?}'/.config/pipewire/hrir.wav", "channel": 0 } },
            { "type": "builtin", "label": "convolver", "name": "convFC", "config": { "filename": "'${HOME:?}'/.config/pipewire/hrir.wav", "channel": 2 } },
            { "type": "builtin", "label": "convolver", "name": "convLFE", "config": { "filename": "'${HOME:?}'/.config/pipewire/hrir.wav", "channel": 3 } },
            { "type": "builtin", "label": "convolver", "name": "convSL_L", "config": { "filename": "'${HOME:?}'/.config/pipewire/hrir.wav", "channel": 4 } },
            { "type": "builtin", "label": "convolver", "name": "convSL_R", "config": { "filename": "'${HOME:?}'/.config/pipewire/hrir.wav", "channel": 5 } },
            { "type": "builtin", "label": "convolver", "name": "convSR_L", "config": { "filename": "'${HOME:?}'/.config/pipewire/hrir.wav", "channel": 5 } },
            { "type": "builtin", "label": "convolver", "name": "convSR_R", "config": { "filename": "'${HOME:?}'/.config/pipewire/hrir.wav", "channel": 4 } },
            { "type": "builtin", "label": "mixer", "name": "mixL" },
            { "type": "builtin", "label": "mixer", "name": "mixR" },
            { "type": "builtin", "label": "copy", "name": "copyFL" },
            { "type": "builtin", "label": "copy", "name": "copyFR" },
            { "type": "builtin", "label": "copy", "name": "copySL" },
            { "type": "builtin", "label": "copy", "name": "copySR" }
        ],
        "links": [
            { "output": "copyFL:Out",   "input": "convFL_L:In" }
            { "output": "copyFL:Out",   "input": "convFL_R:In" }
            { "output": "copyFR:Out",   "input": "convFR_R:In" }
            { "output": "copyFR:Out",   "input": "convFR_L:In" }
            { "output": "copySL:Out",   "input": "convSL_L:In" }
            { "output": "copySL:Out",   "input": "convSL_R:In" }
            { "output": "copySR:Out",   "input": "convSR_R:In" }
            { "output": "copySR:Out",   "input": "convSR_L:In" }
            { "output": "convFL_L:Out", "input": "mixL:In 1" }
            { "output": "convFR_L:Out", "input": "mixL:In 2" }
            { "output": "convFC:Out",   "input": "mixL:In 3" }
            { "output": "convLFE:Out",  "input": "mixL:In 4" }
            { "output": "convSL_L:Out", "input": "mixL:In 5" }
            { "output": "convSR_L:Out", "input": "mixL:In 6" }
            { "output": "convFL_R:Out", "input": "mixR:In 1" }
            { "output": "convFR_R:Out", "input": "mixR:In 2" }
            { "output": "convFC:Out",   "input": "mixR:In 3" }
            { "output": "convLFE:Out",  "input": "mixR:In 4" }
            { "output": "convSL_R:Out", "input": "mixR:In 5" }
            { "output": "convSR_R:Out", "input": "mixR:In 6" }
        ],
        "inputs":  [ "copyFL:In" "copyFR:In" "convFC:In" "convLFE:In" "copySL:In" "copySR:In" ],
        "outputs": [ "mixL:Out" "mixR:Out" ]
    },
    capture.props = {
        "media.class": "Audio/Sink",
        "audio.channels": 6,
        "audio.position": [ FL FR FC LFE SL SR ],
        "node.dont-fallback": true,
        "node.linger": true,
        "stream.dont-remix": true,
        "channelmix.normalize": false
    },
    playback.props = {
        "node.passive": true,
        "audio.channels": 2,
        "audio.position": [ FL FR ],
        "stream.dont-remix": true,
        "channelmix.normalize": false
    }
}'
#
#             { "output": "convFC:Out",   "input": "mixL:In 3", "gain": "+3dB" }
#             { "output": "convLFE:Out",  "input": "mixL:In 4" }
#             { "output": "convSL_L:Out", "input": "mixL:In 5" }
#             { "output": "convSR_L:Out", "input": "mixL:In 6" }
#             { "output": "convFL_R:Out", "input": "mixR:In 1" }
#             { "output": "convFR_R:Out", "input": "mixR:In 2" }
#             { "output": "convFC:Out",   "input": "mixR:In 3", "gain": "+3dB" }
#
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
pid_file="${XDG_RUNTIME_DIR:?}/${virtual_surround_sink_name:?}.pid"
service_name="${virtual_surround_sink_name:?}.service"
service_file="${HOME:?}/.config/systemd/user/${service_name:?}"
run_script="${HOME:?}/.config/pipewire/run.sh"
dummy_virtual_sink_path="${HOME:?}/.config/pipewire/pipewire.conf.d/virtual-sink.conf"
service_config=$( 
    cat <<EOF
[Unit]
Description=${virtual_surround_sink_description:?}
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
run_script_contents=$( 
    cat <<EOF
#!/bin/bash
set -euo pipefail

cleanup() {
    echo "Missing service script at '${script_directory:?}/service.sh'. Cleaning up systemd unit: ${service_name}"
    systemctl --user disable "${service_name}" >/dev/null 2>&1 || true
    rm -f "${service_file}" >/dev/null 2>&1 || true
    systemctl --user daemon-reload >/dev/null 2>&1 || true
    if [[ -f "${dummy_virtual_sink_path:?}" ]]; then
        rm -f "${dummy_virtual_sink_path:?}" >/dev/null 2>&1 || true
    fi
    rm -f "${run_script:?}" >/dev/null 2>&1 || true
}

echo "Checking for service script..."
if [[ ! -f "${script_directory:?}/service.sh" ]]; then
    cleanup
    exit 0
fi

exec "${script_directory:?}/service.sh" run
EOF
)

kill_all_running_instances() {
    if [ -f "${pid_file:?}" ]; then
        cat "${pid_file:?}"
        kill -TERM $(cat "${pid_file:?}") || true
        rm -f "${pid_file:?}"
    fi
    running_pids=$(ps aux | grep -i "pw-cli -m load-module" | grep -v grep | grep "${virtual_surround_sink_name:?}" | awk '{print $2}')
    if [ -n "${running_pids}" ]; then
        kill -TERM ${running_pids}
    fi
}

run() {
    echo "Running service"
    local channels="8"
    while [[ $# -gt 0 ]]; do
        case "$1" in
        --channels=*)
            channels="${1#*=}"
            ;;
        --channels)
            shift
            channels="$1"
            ;;
        *)
            echo "Invalid arg: $1"
            print_usage_and_exit 1
            ;;
        esac
        shift
    done

    # Configure the module args to use
    if [[ "$channels" != "6" && "$channels" != "8" ]]; then
        echo "Invalid channels value: $channels. Must be 6 or 8."
        exit 1
    fi
    local module_args="${args_8}"
    if [[ "$channels" != "8" ]]; then
        module_args="${args_6}"
    fi

    if [ -f "${pid_file:?}" ]; then
        kill -TERM $(cat "${pid_file:?}") 2>/dev/null || true
        rm -f "${pid_file:?}"
        sleep 0.2
    fi
    if pw-cli ls Node | grep "node.name" | grep -q "input.${virtual_surround_sink_name:?}" &>/dev/null; then
        echo "ERROR! A node with the name '${virtual_surround_sink_name:?}' already exists. Exit!"
        exit 1
    fi

    echo "Creating and loading module ${module_name:?} with ${channels:?} channels - ${virtual_surround_sink_name:?}"
    pw-cli -m load-module ${module_name:?} ${module_args:?} &
    pw_cli_pid=$!
    echo ${pw_cli_pid:?} >${pid_file:?}
    sleep 1 # <- sleep for a second to ensure everything is loaded before linking

    # # Set this as the default sink
    # wpctl set-default $(wpctl status | grep 'input.virtual-surround-sound' | grep 'Audio/Sink' | sed 's/[^0-9]*\([0-9]\+\)\..*/\1/')
    # wpctl set-default $(wpctl status | grep 'Audio/Sink' | grep -v 'virtual' | head -n1 | sed 's/[^0-9]*\([0-9]\+\)\..*/\1/')


    ## # Configure loaded module
    ## #   NOTE:
    ## #       The available outputs and inputs are found by running 'pw-link -o' and 'pw-link -i'
    ## echo "Link outputs of module ${module_name:?} - ${virtual_surround_sink_name:?} to module ${virtual_sink_name:?}"
    ## virtual_surround_sink_outputs_prefix="output.${virtual_surround_sink_name:?}:output_"
    ## virtual_sink_inputs_prefix="input.${virtual_sink_name:?}:playback_"
    ## for ch in FL FR; do
    ##     local output="${virtual_surround_sink_outputs_prefix:?}${ch:?}"
    ##     local input="${virtual_sink_inputs_prefix:?}${ch:?}"
    ##     # Attempt to disconnect the link; ignore any errors.
    ##     pw-link --disconnect "${output:?}" "${input:?}" >/dev/null 2>&1 || true
    ##     # Now (re)connect the link.
    ##     echo "${output:?} -> ${input:?}"
    ##     if ! pw-link "${output:?}" "${input:?}"; then
    ##         _term
    ##         echo "An error occured when linking nodes. Unable to proceed. Exit!"
    ##         exit 2
    ##     fi
    ## done

    # Wait for child process to exit:
    echo "Waiting for PID '${pw_cli_pid}' to exit"
    wait "$pw_cli_pid"

    echo "DONE"
}

speaker_test() {
    echo "Running sound test"
    local pulse_sink="${virtual_surround_sink_name:?}"
    while [[ $# -gt 0 ]]; do
        case "$1" in
        --sink=*)
            pulse_sink="${1#*=}"
            ;;
        --sink)
            shift
            pulse_sink="$1"
            ;;
        *)
            echo "Invalid arg: $1"
            print_usage_and_exit 1
            ;;
        esac
        shift
    done
    if [[ "$pulse_sink" != "${virtual_surround_sink_name:?}" && "$pulse_sink" != "${virtual_sink_name:?}" ]]; then
        echo "Select sink: $pulse_sink. Must be ${virtual_surround_sink_name:?} or ${virtual_sink_name:?}."
        exit 1
    fi

    for i in {0..6}; do
        speaker-test -D "pulse:input.${pulse_sink:?}" -c 8 -t wave -s $((i + 1))
    done
    speaker-test -D "pulse:input.${pulse_sink:?}" -c 8 -t sine -f 50 -s 8
}

install_service() {
    echo "Installing service: ${service_name:?}"
    local install_dummy_virtual_sink="false"
    while [[ $# -gt 0 ]]; do
        case "$1" in
        --install-dummy-virtual-sink)
            install_dummy_virtual_sink="true"
            ;;
        *)
            echo "Invalid arg: $1"
            print_usage_and_exit 1
            ;;
        esac
        shift
    done
    if [[ "${install_dummy_virtual_sink:?}" = "true" ]]; then
        # For now, only install this if the virtual sink exists. If it does not, then we will ignore it
        echo "  - Creating directory: '${HOME:?}/.config/pipewire/pipewire.conf.d'"
        mkdir -p \
            "${HOME:?}/.config/pipewire/tmp" \
            "${HOME:?}/.config/pipewire/pipewire.conf.d"
        # Only install and restart pipewire if the config has changed
        local dummy_virtual_sink_tmp="${HOME:?}/.config/pipewire/tmp/virtual-sink.conf"
        echo "${dummy_virtual_sink_2:?}" >"${dummy_virtual_sink_tmp:?}"
        local dummy_virtual_sink_modified="false"
        if [[ ! -f "${dummy_virtual_sink_path:?}" ]]; then
            dummy_virtual_sink_modified="true"
        elif ! cmp -s "${dummy_virtual_sink_tmp:?}" "${dummy_virtual_sink_path:?}"; then
            dummy_virtual_sink_modified="true"
        fi
        if [[ "${dummy_virtual_sink_modified:-}" = "true" ]]; then
            echo "  - Installing dummy virtual-sink.conf"
            cp -f "${dummy_virtual_sink_tmp:?}" "${dummy_virtual_sink_path:?}"
            echo "  - Restarting wireplumber pipewire pipewire-pulse systemd services"
            systemctl --user restart wireplumber pipewire pipewire-pulse
        else
            echo "  - The dummy virtual-sink.conf has not changed"
        fi
    fi
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
    echo "  - Starting systemd service"
    systemctl --user start "${service_name:?}"
    echo "Systemd service installed and started."
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
        echo "  - Removing custom virtual-sink.conf"
        rm -f "${dummy_virtual_sink_path:?}"
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
    echo "Usage: $0 {run|install|uninstall|restart|stop|kill-all} [--channels=<6|8>] [additional args...]"
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
