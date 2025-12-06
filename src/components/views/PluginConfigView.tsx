import {
  PanelSection,
  PanelSectionRow,
  DialogButton,
  Focusable,
  Dropdown, Navigation, Router, ToggleField,
} from '@decky/ui'
import { useState, useEffect } from 'react'
import { MdArrowBack, MdSurroundSound, MdWeb } from 'react-icons/md'
import { SiDiscord, SiGithub, SiKofi, SiPatreon } from 'react-icons/si'
import { HrirFile, PluginConfig } from '../../interfaces'
import { getPluginConfig, setPluginConfig } from '../../constants'
import { call } from '@decky/api'
import { PanelSocialButton } from '../elements/SocialButton'
import { VscSurroundWith } from 'react-icons/vsc'
import { popupNotesDialog } from '../elements/NotesDialog'

interface PluginConfigViewProps {
  onGoBack: () => void;
}

const PluginConfigView: React.FC<PluginConfigViewProps> = ({ onGoBack }) => {
  const [isLoading, setIsLoading] = useState(false)
  const [currentConfig, setCurrentConfig] = useState(() => getPluginConfig())
  const [hrirFileList, setHrirFileList] = useState<HrirFile[]>([])
  const [surroundSinkDefaultConfig, setSurroundSinkDefaultConfig] = useState<boolean>(false)

  const readBackendConfig = async () => {
    const surroundSinkDefault = await call<[], boolean[]>('get_surround_sink_default')
    if (surroundSinkDefault) {
      setSurroundSinkDefaultConfig(true)
    } else {
      setSurroundSinkDefaultConfig(false)
    }
  }

  const updateHrirFileListList = async () => {
    setIsLoading(true)
    try {
      const hrirFiles = await call<[], HrirFile[]>('get_hrir_file_list')
      setHrirFileList(hrirFiles || [])
    } catch (error) {
      console.error('[decky-virtual-surround-sound:PluginConfigView] Error fetching game details:', error)
    } finally {
      setIsLoading(false)
    }
  }

  const updateConfig = (updates: Partial<PluginConfig>) => {
    // Update the localStorage config
    setPluginConfig(updates)
    // Update the local state of component
    setCurrentConfig((prevConfig: PluginConfig) => ({
      ...prevConfig,
      ...updates,
    }))
  }

  const handleHrirSelection = async (hrirName: string) => {
    const selectedHrir = hrirFileList.find((file) => file.label === hrirName)
    if (!selectedHrir) {
      console.error(`[decky-virtual-surround-sound:PluginConfigView] HRIR file not found for name: ${hrirName}`)
      return
    }
    const hrirPath = selectedHrir.path
    const result = await call<[hrirPath: string], boolean>('set_hrir_file', hrirPath)
    if (!result) {
      console.error('[decky-virtual-surround-sound:PluginConfigView] Error saving new HRIR file:', result)
    } else {
      updateConfig({ hrirName: hrirName })
    }
  }

  const handleEnableSurroundDefaultSink = async (enabled: boolean) => {
    console.log(`[decky-virtual-surround-sound:PluginConfigView] Configure Virtual Surround Sink as default: ${enabled}`)
    if (!currentConfig?.notesAcknowledgedV1) {
      console.log(`[decky-virtual-surround-sound:PluginConfigView] Divert to first display warnings dialog.`)
      popupNotesDialog(() => {
        console.log(`[decky-virtual-surround-sound:PluginConfigView] Reloading settings.`)
        setCurrentConfig(getPluginConfig())
      })
      return
    }
    try {
      if (enabled) {
        await call<[], boolean>('enable_surround_sink_default')
      } else {
        await call<[], boolean>('disable_surround_sink_default')
      }
      await readBackendConfig()
    } catch (error) {
      console.error(`[decky-virtual-surround-sound:PluginConfigView] Error setting default sink as ${enabled}:`, error)
    }
  }

  const runSoundTest = async (sink: string) => {
    console.info(`[decky-virtual-surround-sound:PluginConfigView] Exec sound test on ${sink}`)
    await call<[original: string]>('run_sound_test', sink)
  }

  useEffect(() => {
    console.log(`[decky-virtual-surround-sound:PluginConfigView] Mounted`)
    readBackendConfig()
    updateHrirFileListList()
  }, [])

  const openWeb = (url: string) => {
    Navigation.NavigateToExternalWeb(url)
    Router.CloseSideMenus()
  }

  return (
    <div>
      <div>
        <PanelSection>
          <Focusable style={{ display: 'flex', alignItems: 'center', gap: '1rem' }}
                     flow-children="horizontal">
            <DialogButton
              style={{ width: '30%', minWidth: 0 }}
              onClick={onGoBack}>
              <MdArrowBack />
            </DialogButton>
          </Focusable>
        </PanelSection>
        <hr />
      </div>
      <PanelSection title="Plugin Configuration">
      </PanelSection>
      {isLoading ? (
        <PanelSection spinner title="Fetching settings..." />
      ) : (
        <div>
          <PanelSection title="Configure Default Audio Sink">
            <PanelSectionRow>
              <ToggleField
                label="Use Virtual Surround Sound as Default Output"
                checked={surroundSinkDefaultConfig}
                onChange={(e) => {
                  handleEnableSurroundDefaultSink(e)
                }}
                disabled={(surroundSinkDefaultConfig === null)}
              />
              <p style={{ fontSize: '0.7rem', marginBottom: '10px' }}>
                Some applications, particularly games and media players, query the system's default audio sink at launch
                to determine the channel layout (e.g., stereo or 7.1 surround).
                <br />
                If the virtual surround sound sink is not set as the default when these apps start, they will typically
                detect only a stereo output and configure their audio accordingly.
                <br />
                Changing the sink afterward won't cause the application to re-query PipeWire for updated channel
                capabilities, meaning the app will continue outputting 2-channel audio even if moved to a multichannel
                sink.
                <br />
                To ensure proper surround sound, the virtual surround sink must be the default before launching the
                application.
              </p>
            </PanelSectionRow>
          </PanelSection>
          <PanelSection title="Select a HRIR file for filter">
            <PanelSectionRow>
              <Dropdown
                rgOptions={hrirFileList.map((hrirFile) => ({
                  label: `${(currentConfig.hrirName === hrirFile.label) ? '✔' : '—'} ${hrirFile.label}`,
                  data: hrirFile.label,
                }))}
                selectedOption={currentConfig.hrirName}
                onChange={(option) => handleHrirSelection(option.data)}
                strDefaultLabel="Select HRIR Profile"
              />
              <p style={{ fontSize: '0.7rem', marginTop: '10px', marginBottom: '10px' }}>
                Choose from the list of Head-Related Impulse Response (HRIR) .wav files, which captures
                how sound is modified by the shape of your head and ears. This will be applied to your
                audio signal, to create a realistic binaural effect, simulating surround sound through
                headphones. Pick a profile (e.g., Atmos, DTS, Steam) that best suits your taste. You can
                also manually supply your own (see below).
              </p>
              <p style={{ fontSize: '0.7rem', marginBottom: '10px' }}>
                If you wish to provide your own HRIR .wav file, you can download it from the HRTF
                Database and install it to <code>~/.config/pipewire/hrir.wav</code>.
                (Changing presets in this plugin will overwrite that file. To prevent this, set it to
                read-only to prevent changes.)
              </p>
            </PanelSectionRow>
            <PanelSectionRow>
              <DialogButton
                style={{ margin: '5px' }}
                onClick={() => {
                  openWeb(`https://airtable.com/appayGNkn3nSuXkaz/shruimhjdSakUPg2m/tbloLjoZKWJDnLtTc`)
                }}>
                <MdWeb /> Go To HRTF Database
              </DialogButton>
            </PanelSectionRow>

            <PanelSectionRow>
              <div style={{
                margin: '20px 5px 0',
                padding: '0px 0px 8px',
                fontSize: '16px',
                fontWeight: '600',
                fontStyle: 'normal',
                textAlign: 'left',
                textDecoration: 'none',
                textIndent: '0',
                textTransform: 'uppercase',
                lineHeight: '20px',
                letterSpacing: '.5px',
              }}>Test your selected HRIR profile
              </div>
              <DialogButton
                style={{ margin: '5px' }}
                onClick={() => runSoundTest('virtual-surround-sound-filter')}
              >
                <MdSurroundSound /> Surround Enabled
              </DialogButton>
              <DialogButton
                style={{ margin: '5px' }}
                onClick={() => runSoundTest('default')}
              >
                <VscSurroundWith /> Surround Disabled
              </DialogButton>
              <p style={{ fontSize: '0.7rem', marginBottom: '10px' }}>
                Compare how audio sounds with and without the virtual surround filter applied.
                <br />
                The top button plays the test sequence with the surround filter enabled, while the
                bottom button plays it through the default Steam Deck audio sink.
                <br />
                Each test cycles through all 7.1 surround positions — Front Left (FL), Front Center
                (FC), Front Right (FR), Side Right (SR), Rear Right (RR), Rear Left (RL), Side Left (SL)
                — ending with a 50Hz Low-Frequency Effects (LFE) tone.
              </p>
            </PanelSectionRow>
          </PanelSection>
          <hr />
          <PanelSection>
            <PanelSocialButton icon={<SiPatreon fill="#438AB9" />} url="https://www.patreon.com/c/Josh5">
              Patreon
            </PanelSocialButton>
            <PanelSocialButton icon={<SiKofi fill="#FF5E5B" />} url="https://ko-fi.com/josh5coffee">
              Ko-fi
            </PanelSocialButton>
            <PanelSocialButton icon={<SiDiscord fill="#5865F2" />} url="https://streamingtech.co.nz/discord">
              Discord
            </PanelSocialButton>
            <PanelSocialButton icon={<SiGithub fill="#f5f5f5" />}
                               url="https://github.com/DeckSettings/decky-virtual-surround-sound">
              Plugin Source
            </PanelSocialButton>
          </PanelSection>
        </div>
      )}
    </div>
  )
}

export default PluginConfigView
