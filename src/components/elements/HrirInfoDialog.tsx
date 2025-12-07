import { ConfirmModal, Focusable, showModal } from '@decky/ui'
import { QRCodeSVG } from 'qrcode.react'
import { TiInfo } from 'react-icons/ti'
import { ScrollableWindowRelative } from './ScrollableWindow'

const HRIR_INFO_MODAL_CLASS = 'hrir-info-dialog-modal'

const hrirDbLinks = [
  {
    label: 'Wikipedia - HRTF',
    url: 'https://en.wikipedia.org/wiki/Head-related_transfer_function',
  },
  {
    label: 'Binaural Audio Explination',
    url: 'https://binaural-audio.slite.page/p/i38zsD7728/Binaural-Audio',
  },
  {
    label: 'Airtable - HRTF Database',
    url: 'https://airtable.com/appayGNkn3nSuXkaz/shruimhjdSakUPg2m/tbloLjoZKWJDnLtTc',
  },
  {
    label: 'LISTEN HRTF Database',
    url: 'http://recherche.ircam.fr/equipes/salles/listen/',
  },
]

export const popupHrirInfoDialog = (onCloseCallback = () => {
}) => {
  let closePopup = () => {
  }

  const handleClose = () => {
    closePopup()
    onCloseCallback()
  }

  const Popup = () => {
    const iconStyle = {
      marginRight: '5px',
      marginLeft: '5px',
      verticalAlign: 'middle',
    }
    const headingStyle = {
      width: '100%',
      display: 'flex',
      alignItems: 'center',
      justifyContent: 'center',
      color: '#2F80ED',
      margin: 0,
    }
    const paragraphStyle = { margin: '0 0 10px', lineHeight: '1.5', fontSize: '13px' }
    const listStyle = { margin: '0 0 12px 20px', lineHeight: '1.5', fontSize: '13px' }
    const codeBlockStyle = {
      background: '#121722',
      borderRadius: '6px',
      padding: '8px 10px',
      fontSize: '12px',
      fontFamily: 'monospace',
      lineHeight: '1.4',
      marginBottom: '12px',
    }

    return (
      <ConfirmModal
        modalClassName={HRIR_INFO_MODAL_CLASS}
        strTitle={
          <p style={headingStyle}>
            <TiInfo style={iconStyle} /> HRIR Help <TiInfo style={iconStyle} />
          </p>
        }
        closeModal={handleClose}
        onEscKeypress={handleClose}
        onCancel={handleClose}
        strOKButtonText="Close"
        bAlertDialog={true}
      >
        <style>
          {`
            .${HRIR_INFO_MODAL_CLASS} .DialogContent {
              width: min(750px, 88vw);
              max-height: 80vh;
            }

            .${HRIR_INFO_MODAL_CLASS} .DialogFooter {
              display: none !important;
            }
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
              <div style={{
                marginTop: 10,
                marginBottom: 10,
                paddingRight: 6
              }}>
                <p style={paragraphStyle}>
                  Each HRIR (Head-Related Impulse Response) WAV file contains a set of very short impulse responses, tiny
                  recordings of how brief sounds reach your left and right ears when they come from different directions.
                  Because your head, ears, and upper body all bend, block, and delay sound in slightly different ways,
                  those recordings capture the timing and tonal changes your brain uses to tell where a sound is in 3D space.
                  In this plugin, apps can send 7.1 surround audio into PipeWire, and the filter uses the HRIR data to reshape
                  that multi-channel signal into a 2-channel binaural mix for headphones that still feels like surround sound around you.
                </p>

                <p style={paragraphStyle}>
                  Everyone’s head and ears are different, so no single HRIR sounds “correct” for everyone. This plugin ships
                  with several HRIR WAV files collected from public sources. It’s normal to try a few different profiles and
                  keep the one that feels most natural and immersive to you.
                </p>

                <p style={paragraphStyle}>
                  If you want to install your own HRIR WAV file, you can. To make sure the plugin uses your file and does not
                  overwrite it, place it at <code>~/.config/pipewire/hrir.wav</code>, mark it read-only, and restart the
                  virtual surround sound service. For example, after downloading a safe HRIR WAV file:
                </p>
                <div style={codeBlockStyle}>
                  mkdir -p ~/.config/pipewire
                  <br />
                  cp /path/to/downloaded/hrir.wav ~/.config/pipewire/hrir.wav
                  <br />
                  chmod 444 ~/.config/pipewire/hrir.wav
                  <br />
                  systemctl --user restart virtual-surround-sound.service
                </div>

                <ul style={listStyle}>
                  <li>
                    While the file is read-only, the plugin will keep using your custom HRIR for all presets and will not
                    overwrite it.
                  </li>
                  <li>
                    If you want the plugin to manage the HRIR again, make the file writable and pick a preset:
                    <div style={codeBlockStyle}>
                      chmod 644 ~/.config/pipewire/hrir.wav
                    </div>
                  </li>
                  <li>
                    Scan the QR codes below or tap the links to open the Airtable database that hosts a large collection of HRIR files.
                  </li>
                </ul>
                <div style={{ display: 'flex', flexWrap: 'wrap', gap: '12px', marginTop: '4px', alignItems: 'flex-start' }}>
                  {hrirDbLinks.map((entry) => (
                    <div
                      key={entry.url}
                      style={{
                        flex: '0 0 120px',
                        minWidth: 120,
                        maxWidth: 120,
                        padding: 8,
                        border: '1px solid rgba(255, 255, 255, 0.15)',
                        borderRadius: 6,
                        textAlign: 'center',
                        background: '#131722',
                      }}
                    >
                      <QRCodeSVG value={entry.url} size={100} marginSize={4} />
                      <div style={{ marginTop: '6px', fontSize: '11px', wordBreak: 'break-word' }}>{entry.label}</div>
                    </div>
                  ))}
                </div>
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
