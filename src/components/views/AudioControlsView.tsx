import {
  staticClasses,
  DialogButton,
  PanelSection,
  PanelSectionRow,
  Focusable, ToggleField, SliderField, Router,
} from '@decky/ui'
import React, { useState, useEffect, useMemo, useCallback, useRef } from 'react'
import {
  MixerProfile,
  PluginConfig,
  PluginPage,
  RunningApp,
  SinkInput,
  SinkInputConsolidated,
  SinkInputFormat,
} from '../../interfaces'
import { MdOutlineWarningAmber, MdSettings } from 'react-icons/md'
import { call } from '@decky/api'
import {
  defaultMixerProfile,
  getCurrentMixerProfile,
  getMixerChannels,
  getPluginConfig, setMixerProfileInBackend,
  setPluginConfig,
} from '../../constants'
import { FaVolumeUp } from 'react-icons/fa'
import { popupNotesDialog } from '../elements/NotesDialog'


interface AudioControlsViewProps {
  onChangePage: (page: PluginPage) => void
}

const AudioControlsView: React.FC<AudioControlsViewProps> = ({ onChangePage }) => {
  const [currentConfig, setCurrentConfig] = useState<PluginConfig | null>(null)
  const [runningApp, setRunningApp] = useState<RunningApp | null>(null)
  const [profile, setProfile] = useState<string>('default')
  const [usePerAppProfiles, setUsePerAppProfiles] = useState<boolean>(false)
  const channels = useMemo(() => getMixerChannels(currentConfig?.channelCount), [currentConfig?.channelCount])
  const [mixerVolumes, setMixerVolumes] = useState<{ [code: string]: number }>(
    defaultMixerProfile.volumes,
  )
  const [sinkInputList, setSinkInputList] = useState<SinkInputConsolidated[]>([])
  const updateApplicationList = async () => {
    // First get the current running app
    const currentRunningApp = Router.MainRunningApp
    if (currentRunningApp) {
      setRunningApp({
        display_name: currentRunningApp.display_name,
      })
    } else {
      setRunningApp(null)
    }
    // Second try to list all current sink inputs from backend
    try {
      const sinkInputs = await call<[], SinkInput[]>('list_sink_inputs')
      if (!sinkInputs) return

      const enabledApps = await call<[], string[]>('get_enabled_apps_list') ?? []

      // Consolidate sink inputs by app name.
      const appMap = new Map<string, SinkInputConsolidated>()
      sinkInputs.forEach((input) => {
        if (typeof input.index !== 'number') {
          return
        }
        const appName = input.name?.trim()
        if (!appName) {
          return
        }
        const enabled = enabledApps.includes(appName)
        const targetObject = input.target_object ?? ''
        const volumeSummary = input.volume ?? ''
        const formatInfo: SinkInputFormat = input.format ?? {
          format: 'Unknown',
          sample_format: '',
          rate: '',
          channels: '',
          channel_map: [],
        }
        if (appMap.has(appName)) {
          const existingApp = appMap.get(appName)!
          const hasFormat = existingApp.formats.some(f =>
            f.format === formatInfo.format &&
            f.sample_format === formatInfo.sample_format &&
            f.rate === formatInfo.rate &&
            f.channels === formatInfo.channels &&
            (f.channel_map || []).join(',') === (formatInfo.channel_map || []).join(','),
          )
          if (!hasFormat) {
            existingApp.formats.push(formatInfo)
          }
          existingApp.index = Math.min(existingApp.index, input.index)
          existingApp.volume = volumeSummary || existingApp.volume
          existingApp.target_object = targetObject || existingApp.target_object
          existingApp.enabled = enabled
        } else {
          // First occurrence of this app, create a new consolidated entry
          appMap.set(appName, {
            name: appName,
            index: input.index,
            formats: [formatInfo],
            volume: volumeSummary,
            target_object: targetObject,
            enabled,
          })
        }
      })
      setSinkInputList(Array.from(appMap.values()))
    } catch (error) {
      console.error('[decky-virtual-surround-sound:AudioControlsView] Error fetching app details:', error)
    }
  }

  // Update mixer profile from backend and update state accordingly.
  const updateMixerProfile = async () => {
    const mixerProfile = await getCurrentMixerProfile()
    setProfile(mixerProfile.name)
    if (mixerProfile.name === 'default') {
      setUsePerAppProfiles(false)
    } else {
      setUsePerAppProfiles(!!(mixerProfile?.usePerAppProfile))
    }
    if (mixerProfile.volumes) {
      setMixerVolumes(mixerProfile.volumes)
    }
    setCurrentConfig(getPluginConfig())
  }

  // Toggle per-app profiles and update the mixer profile afterward.
  const togglePerAppProfiles = async (enabled: boolean) => {
    console.log(`[decky-virtual-surround-sound:AudioControlsView] Toggle per-app profile: ${enabled}`)
    setUsePerAppProfiles(enabled)
    if (runningApp?.display_name) {
      setPluginConfig({
        perAppProfiles: {
          [runningApp.display_name]: {
            name: runningApp.display_name,
            usePerAppProfile: enabled,
          },
        },
      })
    } else {
      // Always set to false if no app is running
      setUsePerAppProfiles(false)
    }
    await updateMixerProfile()
  }

  const updateChannelVolume = useCallback(
    async (channel: string, value: number) => {
      console.log(`[decky-virtual-surround-sound] Setting ${channel} volume to ${value}`)
      const updatedVolumes = { ...mixerVolumes, [channel]: value }
      const mixerProfile: MixerProfile = {
        name: profile,
        volumes: updatedVolumes,
      }
      // Save plugin config
      setPluginConfig({
        perAppProfiles: {
          ...currentConfig?.perAppProfiles,
          [profile]: mixerProfile,
        },
      })
      // Save send updated mixer profile to backend
      await setMixerProfileInBackend(mixerProfile)
      //await call<[MixerProfile], boolean>('set_mixer_profile', mixerProfile);
    },
    [mixerVolumes, currentConfig, profile],
  )
  const channelDebounceRef = useRef(
    new Map<string, { timer: ReturnType<typeof setTimeout>; value: number }>(),
  )
  const handleVolumeChange = (channel: string, value: number) => {
    const updatedVolumes = { ...mixerVolumes, [channel]: value }
    setMixerVolumes(updatedVolumes)

    // Flush pending debounce timers for any channels that are not the current one.
    channelDebounceRef.current.forEach((entry, ch) => {
      if (ch !== channel) {
        clearTimeout(entry.timer)
        // Commit the pending update immediately for that channel.
        updateChannelVolume(ch, entry.value)
        channelDebounceRef.current.delete(ch)
      }
    })

    // For the current channel, if there's an existing timer, clear it.
    if (channelDebounceRef.current.has(channel)) {
      clearTimeout(channelDebounceRef.current.get(channel)!.timer)
    }

    // Set a new timer for the current channel.
    const timer = setTimeout(() => {
      updateChannelVolume(channel, value)
      channelDebounceRef.current.delete(channel)
    }, 250)

    // Store (or update) the pending timer and value for this channel.
    channelDebounceRef.current.set(channel, { timer, value })
  }

  const handleAppSelect = async (app: SinkInputConsolidated, enabled: boolean) => {
    console.log(`[decky-virtual-surround-sound:AudioControlsView] Setting app to state ${enabled} [Title:${app.name}]`)
    if (!currentConfig?.notesAcknowledgedV1) {
      console.log(`[decky-virtual-surround-sound:AudioControlsView] Divert to first display warnings dialog.`)
      popupNotesDialog(() => {
        console.log(`[decky-virtual-surround-sound:AudioControlsView] Reloading settings.`)
        setCurrentConfig(getPluginConfig())
      })
      return
    }
    if (app.target_object.trim() !== '') return
    try {
      if (enabled) {
        await call<[string], boolean>('enable_for_app', app.name)
      } else {
        await call<[string], boolean>('disable_for_app', app.name)
      }
      await updateApplicationList()
    } catch (error) {
      console.error(`[decky-virtual-surround-sound:AudioControlsView] Error toggling app ${app.name}:`, error)
    }
  }

  useEffect(() => {
    setCurrentConfig(getPluginConfig())
    updateApplicationList()
    updateMixerProfile()
    // Add loop to update options
    const interval = setInterval(() => {
      updateApplicationList()
      //updateMixerProfile(); // Not sure if this needs to be updated. Probably only needs to be run once on load.
    }, 5000)
    return () => clearInterval(interval)
  }, [])

  return (
    <>
      <div>
        <PanelSection>
          <Focusable style={{ display: 'flex', alignItems: 'center', gap: '1rem' }}
            flow-children="horizontal">
            <DialogButton
              style={{ width: '100%', minWidth: 0 }}
              onClick={() => onChangePage('plugin_config')}>
              <MdSettings /> Plugin Settings
            </DialogButton>
          </Focusable>
        </PanelSection>
        <hr />
      </div>
      {sinkInputList.length === 0 ? (
        <div style={{
          textAlign: 'center',
          fontSize: '0.8rem',
          color: '#aaa',
          marginTop: '10px',
          padding: '10px',
        }}>
          🎵 No active applications are playing audio right now.
        </div>
      ) : (
        <>
          <div className={staticClasses.PanelSectionTitle} style={{ marginLeft: '10px' }}>Sources</div>
          {sinkInputList.map((app) => (
            <PanelSection key={app.index} title={app.name}>
              <PanelSectionRow>
                <div style={{
                  padding: 0,
                  margin: 0,
                  borderLeft: 'thin dotted',
                }}>
                  <ul style={{
                    listStyle: 'none',
                    fontSize: '0.7rem',
                    margin: 0,
                    paddingLeft: '5px',
                    paddingRight: 0,
                    paddingTop: 0,
                    paddingBottom: '3px',
                  }}>
                    {app.formats.map((format, index) => (
                      <li key={index}
                        style={{
                          display: 'table',
                          textAlign: 'right',
                          width: '100%',
                          borderBottom: '1px solid #333',
                          paddingTop: '2px',
                          paddingBottom: '2px',
                        }}>
                        <strong style={{
                          display: 'table-cell',
                          textAlign: 'left',
                          paddingRight: '3px',
                        }}>Audio #{index}:</strong>
                        {format.format}_{format.sample_format}, {format.rate}Hz, {format.channels} channels
                      </li>
                    ))}
                    {app.target_object.trim() !== '' && (
                      <li style={{
                        display: 'table',
                        textAlign: 'left',
                        width: '100%',
                        borderBottom: '1px solid #333',
                        paddingTop: '2px',
                        paddingBottom: '2px',
                      }}>
                        <MdOutlineWarningAmber style={{ color: 'orange', marginRight: '3px' }} />
                        <strong> NOTE: </strong>
                        This app has specifically targeted an output and cannot be edited here.
                        Try editing audio output from within the app.
                      </li>
                    )}
                  </ul>
                  <div style={{
                    margin: 0,
                    paddingLeft: '5px',
                    paddingRight: '5px',
                    paddingTop: 0,
                    paddingBottom: 0,
                    overflow: 'hidden',
                  }}>
                    <ToggleField
                      label="Enable"
                      description="Enable Virtual Surround Sound filter for this app"
                      checked={app.enabled}
                      onChange={(e) => {
                        handleAppSelect(app, e)
                      }}
                      disabled={app.target_object.trim() !== ''}
                    />
                  </div>
                </div>
              </PanelSectionRow>
            </PanelSection>
          ))}
        </>
      )}
      <hr />
      <div className={staticClasses.PanelSectionTitle} style={{ marginLeft: '10px' }}>Mixer</div>
      <PanelSection>
        <PanelSectionRow>
          {/*TODO: Add app icon*/}
          {/*<div>Using {profile} profile</div>*/}
          <ToggleField
            label="Use per-game profile"
            description={`Using ${profile} profile`}
            checked={usePerAppProfiles}
            disabled={(runningApp === null)}
            onChange={(e) => {
              togglePerAppProfiles(e)
            }}
          />
        </PanelSectionRow>
        {/*Volume mixer*/}
        <PanelSectionRow>
          {channels.map(({ code, label }) => (
            <SliderField
              key={code}
              min={0}
              max={150}
              step={5}
              notchCount={4}
              notchTicksVisible={false}
              label={label}
              showValue
              layout="inline"
              bottomSeparator="none"
              icon={<FaVolumeUp />}
              value={mixerVolumes[code] ?? 100}
              onChange={(value: number) => {
                handleVolumeChange(code, value)
              }}
            />
          ))}
        </PanelSectionRow>
      </PanelSection>
    </>
  )
}

export default AudioControlsView
