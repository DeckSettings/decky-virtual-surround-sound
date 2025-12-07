import { ConfirmModal, Focusable, showModal } from '@decky/ui'
import { ScrollableWindowRelative } from './ScrollableWindow'
import { TiInfo } from 'react-icons/ti'
import { MdOutlineWarningAmber } from 'react-icons/md'
import { setPluginConfig } from '../../constants'

const VSS_HELP_MODAL_CLASS = 'vss-help-dialog-modal'

interface PopupVssHelpDialogOptions {
  hideAcknowledge?: boolean
}

export const popupVssHelpDialog = (
  onCloseCallback = () => { },
  options?: PopupVssHelpDialogOptions,
) => {
  let closePopup = () => { }

  const showAcknowledge = !options?.hideAcknowledge

  const handleClose = () => {
    closePopup()
    onCloseCallback()
  }

  const footerStyle = showAcknowledge
    ? ''
    : `
            .${VSS_HELP_MODAL_CLASS} .DialogFooter {
              display: none !important;
            }
          `

  const Popup = () => {
    const iconStyle = {
      marginRight: '5px',
      marginLeft: '5px',
      verticalAlign: 'middle',
    }
    const titleStyle = {
      width: '100%',
      display: 'flex',
      alignItems: 'center',
      justifyContent: 'center',
      color: 'steelblue',
      margin: 0,
    }
    const paragraphStyle = { margin: '0 0 10px', lineHeight: '1.5', fontSize: '13px' }
    const italicStyle = { ...paragraphStyle, fontStyle: 'italic' }
    const codeBlockStyle = {
      background: '#121722',
      borderRadius: '6px',
      padding: '8px 8px',
      fontSize: '12px',
      fontFamily: 'monospace',
      lineHeight: '1.4',
      marginBottom: '12px',
    }

    return (
      <ConfirmModal
        modalClassName={VSS_HELP_MODAL_CLASS}
        strTitle={
          <p style={titleStyle}>
            <TiInfo style={iconStyle} /> Virtual Surround Sound Help <TiInfo style={iconStyle} />
          </p>
        }
        closeModal={handleClose}
        onEscKeypress={handleClose}
        onCancel={handleClose}
        strOKButtonText={showAcknowledge ? 'Acknowledge' : undefined}
        bAlertDialog={showAcknowledge}
        onOK={
          showAcknowledge
            ? () => {
              console.log(`[decky-virtual-surround-sound:DefaultSinkDialog] Setting as acknowledged.`)
              setPluginConfig({ notesAcknowledgedV2: true })
              handleClose()
            }
            : undefined
        }
      >
        <style>
          {`
            .${VSS_HELP_MODAL_CLASS} .DialogContent {
              width: min(750px, 88vw);
              max-height: 80vh;
            }
            ${footerStyle}
          `}
        </style>
        <div
          style={{
            height: '50vh',
            width: '-webkit-fill-available',
            position: 'relative',
          }}
        >
          <Focusable
            style={{
              display: 'flex',
              flexDirection: 'column',
              height: '100%',
            }}
          >
            <ScrollableWindowRelative
              heightPercent={100}
              onCancel={handleClose}
            >
              <div style={{ marginTop: 10, marginBottom: 10, paddingRight: 6 }}>
                <p style={paragraphStyle}>
                  Installing this plugin creates a special audio path called "Virtual Surround Sound" behind the scenes. In
                  SteamOS Game Mode it does not appear in the normal audio output list, and it is controlled only from this
                  plugin. By default your usual speakers or headphones stay as the system output. You need to decide in the
                  plugin settings whether you want to send your audio through Virtual Surround Sound for processing.
                </p>

                <p style={paragraphStyle}>
                  If you set the Virtual Surround Sound sink as your default output in the plugin settings, apps and games will
                  see it as the main device from the moment they start. Many titles, especially games launched through Proton,
                  look at the default ALSA or PulseAudio device during startup and lock in whatever channel layout they find.
                  If the default device only offers 2 channels, those games will usually output stereo for the entire session.
                  If the default is the Virtual Surround Sound sink with 8 channels, they can send real 5.1 or 7.1 audio that the plugin
                  can then mix down to a 2 channel binaural signal for your headphones.
                </p>

                <p style={paragraphStyle}>
                  You can check what an app is sending by looking at the status line at the top of this plugin view. It will
                  show something like <code style={codeBlockStyle}>pcm_float32le, 48000Hz, 8 channels</code> for 7.1 surround or
                  <code style={codeBlockStyle}>6 channels</code> for 5.1. If it stays at <code style={codeBlockStyle}>2 channels</code>,
                  the app is only sending stereo. The filter can still apply headphone processing to stereo, but it cannot
                  recreate separate surround speakers if the game never outputs them.
                </p>

                <p style={paragraphStyle}>
                  The plugin also has per app controls that can move individual games or players to the Virtual Surround Sound
                  sink when Steam launches them. Native Linux applications like Moonlight, web browsers or media players often update
                  their audio stream when you switch sinks, so this works well. Most Proton games do not renegotiate their channel
                  count after launch, so they benefit the most when the Virtual Surround Sound sink is already the default device
                  before they start.
                </p>

                <p style={paragraphStyle}>
                  Many modern games also include a <span style={{ fontStyle: 'italic' }}>"Headphones"</span> or
                  <span style={{ fontStyle: 'italic' }}>"3D audio"</span> option in their audio settings. These modes usually
                  apply their own binaural processing inside the game engine using the true 3D positions of sounds. In most cases
                  they sound more natural and accurate than forcing a <span style={{ fontStyle: 'italic' }}>"home theatre"</span>
                  or <span style={{ fontStyle: 'italic' }}>"7.1"</span> speaker mode through Virtual Surround Sound and having it
                  down mix everything to two channels.
                </p>

                <div
                  style={{
                    padding: 12,
                    marginBottom: 10,
                    border: '1px solid rgba(191, 193, 198, 0.4)',
                    borderRadius: 8,
                    background: '#14171c',
                    display: 'flex',
                    flexDirection: 'column',
                    gap: 6,
                  }}
                >
                  <div style={{ display: 'flex', alignItems: 'center', gap: '6px', fontWeight: 600, color: '#c0c4cc' }}>
                    <TiInfo size={16} />
                    Note
                  </div>
                  <p style={{ ...paragraphStyle, marginBottom: 0 }}>
                    It is recommended that you use a game's headphone or 3D audio option whenever it is available. These modes
                    usually deliver better positional accuracy than routing the game through a speaker focused 5.1 or 7.1 mode and
                    asking this plugin to down mix it. Only rely on Virtual Surround Sound's filter for surround virtualization
                    when the game does not provide a good built in headphone or 3D audio option.
                  </p>
                </div>

                <p style={paragraphStyle}>
                  There are some downsides to setting the Virtual Surround Sound sink as the default. Certain outputs may not switch
                  over cleanly, and some devices might behave oddly if they expect to be the default themselves. If you notice
                  missing audio, strange routing, or devices that refuse to follow your settings, turn off the
                  <span style={{ fontStyle: 'italic', fontWeight: 'bold' }}>"Use Virtual Surround Sound as Default Output"</span> option
                  and try again. You should also avoid using this feature when you connect to an external multichannel system such as a
                  home theatre receiver or soundbar. This plugin is designed to down mix surround to 2 channels for headphones, not to
                  feed real 5.1 or 7.1 speakers.
                </p>

                <div
                  style={{
                    padding: 12,
                    marginBottom: 10,
                    border: '1px solid #B78FFF',
                    borderRadius: 8,
                    background: '#1C1238',
                    display: 'flex',
                    flexDirection: 'column',
                    gap: 6,
                  }}
                >
                  <div style={{ display: 'flex', alignItems: 'center', gap: '6px', fontWeight: 600, color: '#B78FFF' }}>
                    <MdOutlineWarningAmber size={18} />
                    Important!
                  </div>
                  <p style={paragraphStyle}>
                    Do not enable "Use Virtual Surround Sound as Default Output" when you connect to an external multichannel
                    system such as a home theatre receiver or surround sound soundbar. Virtual Surround Sound is designed to
                    take 5.1 or 7.1 surround from games and mix it down into 2 channel binaural audio for headphones, not to
                    feed real 5.1 or 7.1 speaker setups.
                  </p>
                  <p style={{ ...paragraphStyle, marginBottom: 0 }}>
                    If you send this 2 channel binaural signal into a receiver that is trying to do its own surround processing,
                    you can lose positional accuracy, get strange effects, or only hear basic stereo from your speakers. In that
                    case, keep your HDMI or receiver output as the default device and use its built in surround features instead
                    of this plugin.
                  </p>
                </div>

                <p style={{ ...italicStyle, marginBottom: 0 }}>TLDR;</p>
                <ul style={{ ...italicStyle, paddingLeft: 20, margin: 0 }}>
                  <li>Keep Virtual Surround Sound as default when you want surround-capable apps to ouput 7.1 channels correctly to headphone.</li>
                  <li>Keep the plugin config option <span style={{ fontStyle: 'italic', fontWeight: 'bold' }}>"Use Virtual Surround Sound as Default Output"</span> disabled for external speaker systems or if audio problems appear.</li>
                  <li>Prefer the in-game headphone/3D audio mode whenever it is available for the best positional accuracy.</li>
                </ul>
              </div>
            </ScrollableWindowRelative>
          </Focusable>
        </div>
      </ConfirmModal>
    )
  }

  const modal = showModal(<Popup />, window)
  closePopup = modal.Close
}
