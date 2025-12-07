// Site URLs
import { Channel, MixerProfile, PluginConfig } from './interfaces'
import { Router } from '@decky/ui'
import { call } from '@decky/api'

export const restartSteamClient = (): void => {
  SteamClient.User.StartRestart(false)
}

export const mergeDeep = (defaultObj: any, sourceObj: any): any => {
  // If sourceObj isn't an object, just return defaultObj (or you could return sourceObj)
  if (typeof sourceObj !== 'object' || sourceObj === null) {
    return defaultObj
  }

  // Start with a shallow copy of the default object.
  const result: any = { ...defaultObj }

  // Iterate over each key in the source object.
  Object.keys(sourceObj).forEach((key) => {
    const sourceVal = sourceObj[key]

    if (result.hasOwnProperty(key)) {
      // If the key exists in both, and both values are plain objects (not arrays), merge them recursively.
      const defaultVal = result[key]
      if (
        typeof defaultVal === 'object' &&
        defaultVal !== null &&
        !Array.isArray(defaultVal) &&
        typeof sourceVal === 'object' &&
        sourceVal !== null &&
        !Array.isArray(sourceVal)
      ) {
        result[key] = mergeDeep(defaultVal, sourceVal)
      } else {
        // Otherwise, override the default with the source value.
        result[key] = sourceVal
      }
    } else {
      // If the key doesn't exist in the default object, add it.
      result[key] = sourceVal
    }
  })

  return result
}

export const defaultMixerProfile = {
  name: 'default',
  usePerAppProfile: false,
  volumes: {
    FL: 100,
    FR: 100,
    FC: 120,
    LFE: 100,
    RL: 80,
    RR: 80,
    SL: 90,
    SR: 90,
  },
}

export const generateUniqueId = (): string => {
  // Use the built-in randomUUID if available
  if (typeof crypto !== 'undefined' && typeof crypto.randomUUID === 'function') {
    return crypto.randomUUID()
  } else if (typeof crypto !== 'undefined' && crypto.getRandomValues) {
    // Create a template string by forcing the first value to a string.
    const template = String(1e7) + -1e3 + -4e3 + -8e3 + -1e11
    return template.replace(/[018]/g, (c) =>
      (Number(c) ^ crypto.getRandomValues(new Uint8Array(1))[0] & 15 >> Number(c) / 4).toString(16),
    )
  }
  // Fallback if crypto is not available
  return Math.random().toString(36).substring(2) + Date.now().toString(36)
}

const pluginSettingsKey = __PLUGIN_NAME__

export const getPluginConfig = (): PluginConfig => {
  const defaultConfig: PluginConfig = {
    notesAcknowledgedV2: false,
    hrirName: 'HRTF from Aureal Vortex 2 - WIP v2',
    channelCount: 8,
    usePerAppProfiles: false,
    perAppProfiles: {
      default: defaultMixerProfile,
    },
  }
  const dataJson = window.localStorage.getItem(pluginSettingsKey)
  let config: PluginConfig = defaultConfig
  if (dataJson) {
    try {
      const parsedConfig = JSON.parse(dataJson)
      // Deep merge the stored config over the defaults:
      config = mergeDeep(defaultConfig, parsedConfig)
    } catch (error) {
      console.error('[decky-virtual-surround-sound:constants] Failed to parse plugin config:', error)
    }
  }
  // If the installation ID is not present, generate one and save it.
  if (!('installationId' in config) || !config.installationId) {
    config.installationId = generateUniqueId()
    window.localStorage.setItem(pluginSettingsKey, JSON.stringify(config))
  }
  return config
}

export const setPluginConfig = (updates: Partial<PluginConfig>): void => {
  const currentConfig = getPluginConfig()
  // Deep merge the updates into the current config:
  const newConfig = mergeDeep(currentConfig, updates)
  try {
    window.localStorage.setItem(pluginSettingsKey, JSON.stringify(newConfig))
  } catch (error) {
    console.error('[decky-virtual-surround-sound:constants] Failed to save plugin config:', error)
  }
}

export const getCurrentProfileFromRunningApp = async (currentConfig: PluginConfig): Promise<string> => {
  let profileName = 'default'
  const currentRunningGame = Router.MainRunningApp
  if (currentRunningGame?.display_name) {
    // If per-app profiles are enabled, and we have a mapping, use the running app's profile.
    if (currentConfig.perAppProfiles) {
      if (currentRunningGame.display_name in currentConfig.perAppProfiles) {
        // Check if per-app profile is enabled from this running app
        const existingProfile = currentConfig.perAppProfiles[currentRunningGame.display_name]
        if (existingProfile.usePerAppProfile) {
          profileName = currentConfig.perAppProfiles[currentRunningGame.display_name].name || currentRunningGame.display_name
        }
      }
    }
  }
  return profileName
}

export const getMixerChannels = (channelCount: number = 8): Channel[] => {
  const channels: Channel[] = [
    { code: 'FL', label: 'Front Left' },
    { code: 'FC', label: 'Front Center' },
    { code: 'FR', label: 'Front Right' },
    { code: 'SL', label: 'Side Left' },
    { code: 'SR', label: 'Side Right' },
    { code: 'LFE', label: 'Subwoofer (LFE)' },
    { code: 'RL', label: 'Rear Left' },
    { code: 'RR', label: 'Rear Right' },
  ]
  if (channelCount === 6) {
    // For a 5.1 setup (6 channels), only return these channels:
    return channels.filter((channel) =>
      ['FL', 'FR', 'FC', 'LFE', 'SL', 'SR'].includes(channel.code),
    )
  }
  return channels
}

// This function updates the mixer profile based on the backend settings and running app.
export const getCurrentMixerProfile = async (): Promise<MixerProfile> => {
  const currentConfig = getPluginConfig()
  // Get selected profile. If per-app profiles are enabled, check for a profile based on the running app.
  const selectedProfileName = await getCurrentProfileFromRunningApp(currentConfig)
  // Lookup the mixer profile settings.
  let mixerProfile: MixerProfile
  if (currentConfig.perAppProfiles &&
    currentConfig.perAppProfiles[selectedProfileName]) {
    mixerProfile = currentConfig.perAppProfiles[selectedProfileName]
  } else {
    mixerProfile = defaultMixerProfile
  }
  // Return mixer profile
  return mixerProfile
}

export const setMixerProfileInBackend = async (mixerProfile: MixerProfile): Promise<void> => {
  // Set this 'mixerProfile' in the backend by sending the whole profile volume list
  await call<[MixerProfile], boolean>('set_mixer_profile', mixerProfile)
}
