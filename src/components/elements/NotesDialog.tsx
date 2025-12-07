import { ConfirmModal, Focusable, showModal } from '@decky/ui'
import { ScrollableWindowRelative } from './ScrollableWindow'
import { TiInfo } from 'react-icons/ti'
import { setPluginConfig } from '../../constants'

const NOTES_MODAL_CLASS = 'notes-dialog-modal'

interface PopupNotesDialogOptions {
  hideAcknowledge?: boolean
}

export const popupNotesDialog = (
  onCloseCallback = () => { },
  options?: PopupNotesDialogOptions,
) => {
  let closePopup = () => {
  }

  // Wrap the modal closing so we can also call the callback.
  const showAcknowledge = !options?.hideAcknowledge

  const handleClose = () => {
    closePopup()
    onCloseCallback()
  }

  let Popup = () => {
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

    return (
      <ConfirmModal
        modalClassName={NOTES_MODAL_CLASS}
        strTitle={
          <p style={titleStyle}>
            <TiInfo style={iconStyle} /> NOTES <TiInfo style={iconStyle} />
          </p>
        }
        closeModal={handleClose}
        onEscKeypress={handleClose}
        onCancel={handleClose}
        strOKButtonText={showAcknowledge ? 'Acknowledge' : undefined}
        bAlertDialog={showAcknowledge}
        onOK={showAcknowledge ? () => {
          console.log(`[decky-virtual-surround-sound:WarningDialog] Setting as acknowledged.`)
          setPluginConfig({ notesAcknowledgedV1: true })
          handleClose()
        } : undefined}
      >
        <style>
          {`
            .${NOTES_MODAL_CLASS} .DialogContent {
              width: min(750px, 88vw);
              max-height: 80vh;
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
            <ScrollableWindowRelative heightPercent={100}>
              <div style={{ marginTop: 10, marginBottom: 10, paddingRight: 6 }}>
                <p style={paragraphStyle}>
                  1) Binaural virtual surround sound produced by this plugin's filter will only work with headphones.
                </p>
                <p style={paragraphStyle}>
                  2) Not every game or app supports outputting more than 2 channels. Even if Pipewire reports
                  8-channel PCM, that may not be the case — you can test this by muting the front-left and front-right
                  channels in the plugin mixer.
                </p>
                <p style={paragraphStyle}>
                  3) In some cases, setting the game to use the Virtual Surround Sound sink in the game settings
                  produces better results than enabling the sink in the plugin. Please test on a per-app basis.
                </p>
                <p style={italicStyle}>
                  Compatibility is not guaranteed; test and tweak settings to achieve the best setup for your system.
                </p>
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
