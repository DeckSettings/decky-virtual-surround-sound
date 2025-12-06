# Decky Virtual Surround Sound

[![Chat](https://img.shields.io/badge/chat-on%20discord-7289da.svg)](https://streamingtech.co.nz/discord)

Decky Virtual Surround Sound is a Decky plugin that provides a virtual audio output device—**Virtual Surround Sound**—for games and applications. By using a custom Pipewire filter-chain module, this plugin converts 7.1 surround sound into immersive binaural audio tailored for headphone use.

> **Note:** This solution is optimized for headphone listeners. While it may work for games targeting surround sound outputs (such as theatre systems), if the game natively supports surround-to-headphone processing, that option is recommended.

Users of this plugin are able to place a custom .wav from the HRTF Database (<https://airtable.com/appayGNkn3nSuXkaz/shruimhjdSakUPg2m/tbloLjoZKWJDnLtTc>) at `~/.config/pipewire/hrir.wav`. Note that changing presets in the plugin config will overwrite this file. Set the file to read-only to prevent this from happening.

## Features

- **Custom Pipewire Filter-Chain:** Loads/unloads a custom filter-chain module via a script to process audio.
- **Binaural Audio Processing:** Uses HRIR-based filtering to convert 7.1 surround audio into binaural output.
- **Multiple HRIR Presets:** Choose from a list of presets including Atmos, DTS, Steam, Razer, Windows Sonic, OpenAL, Realtek, etc.
- **Per-App/Game Enablement:** Activate the virtual surround sound output on a per-game or per-application basis through the plugin UI.
- **User-Friendly Interface:** Easily enable/disable the effect without complex configuration.

## Prerequisites

- A Decky environment with support for custom plugins.
- A system running Pipewire with the ability to load/unload custom modules.
- Headphones are strongly recommended for the best experience.

## Developers

### Dependencies

This relies on the user having Node.js v18+ and `pnpm` (v9) installed on their system.  
Please make sure to install pnpm v9 to prevent issues with CI during plugin submission.  
`pnpm` can be downloaded from `npm` itself which is recommended.

#### Linux

```bash
npm i -g pnpm@9
```

### Building Virtual Surround Sound

1. Clone the repository.
2. In your local fork/own plugin-repository run these commands:
   1. `pnpm i`
   2. `ln -sf ./defaults/service.sh ./service.sh`
   3. `ln -sf ./defaults/hrir-audio ./hrir-audio`
   4. `ln -sf ./defaults/hrtf-sofa ./hrtf-sofa`
   5. `pnpm run build`
      - These setup pnpm and build the frontend code for testing.
3. Use the [decky-frontend-lib](https://github.com/SteamDeckHomebrew/decky-frontend-lib) documentation to integrate additional functionality as needed.
4. If using VSCodium/VSCode, run the `setup` and `build` and `deploy` tasks. If not using VSCodium etc. you can derive your own makefile or just manually utilize the scripts for these commands as you see fit.

If you use VSCode or it's derivatives (we suggest [VSCodium](https://vscodium.com/)!) just run the `setup` and `build` tasks. It's really that simple.

#### Rebuilding After Code Changes

Everytime you change the frontend code (`index.tsx` etc) you will need to rebuild using the commands from step 2 above or the build task if you're using vscode or a derivative.

Note: If you are receiving build errors due to an out of date library, you should run this command inside of your repository:

```bash
pnpm update @decky/ui --latest
```

### Development environment

Install some useful tools

```bash
python3 -m venv venv --clear
source venv/bin/activate

python3 -m pip install pulsemixer

```

Create a symlink to the stuff in `defaults` so that the plugin can use them

```bash
ln -sf ./defaults/hrir-audio hrir-audio
ln -sf ./defaults/service.sh service.sh
```

Install virtual surround sound service

```bash
./service.sh install
```

Run the CLI

```bash
python ./main.py 
```

## Notes on how this works on SteamOS

SteamOS ships with PipeWire for low-latency audio handling and WirePlumber as its default session manager. WirePlumber negotiates which nodes become available to the desktop and what devices Steam exposes in Settings, while PipeWire handles the actual DSP graph. Decky Virtual Surround Sound slots into that graph by loading a custom `module-filter-chain` definition that mixes 7.1 input down to binaural headphone output.

Instead of dropping a static filter-chain file into `~/.config/pipewire`, the plugin installs a user-level systemd unit that calls `service.sh`. The script dynamically loads and unloads the filter through PipeWire's CLI so the module is registered immediately, without needing to restart PipeWire or WirePlumber (those restarts tend to upset Steam until you reboot the client). This approach also keeps Steam's Audio Output list clean: the filter is advertised directly to PipeWire so it just appears as another routable node rather than an extra, confusing device entry inside Steam Settings.

The filter itself relies on Head Related Impulse Response (HRIR) data. HRIR files capture how sound at different angles reaches real human ears, combining the effects of head, torso, and outer ear reflections into short impulse responses. When convolving speaker channels with HRIRs, we approximate how a surround speaker layout would sound through headphones, delivering the virtual surround effect. The plugin ships with several curated HRIR sets, and you can experiment with others. A good catalog of measured HRIRs lives at [HRTF Database](https://airtable.com/appayGNkn3nSuXkaz/shruimhjdSakUPg2m/tbloLjoZKWJDnLtTc).

During startup, the systemd unit runs `service.sh` which writes the selected HRIR into `~/.config/pipewire/hrir.wav`, ensures the filter parameters match your preset, and issues the PipeWire commands required to (re)load the module. Because everything happens in-process, switching presets or enabling/disabling the plugin is instantaneous and doesn’t interfere with the rest of the audio stack.
