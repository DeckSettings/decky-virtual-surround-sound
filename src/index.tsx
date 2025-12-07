import {
  definePlugin,
  // routerHook
} from '@decky/api'
import QuickAccessMenuRouter from './components/QuickAccessMenuRouter'
import { MdSurroundSound } from 'react-icons/md'
import { getCurrentMixerProfile, setMixerProfileInBackend } from './constants'

let mixerProfileListenerIntervalId: undefined | number

const currentProfileListener = () => {
  mixerProfileListenerIntervalId = window.setInterval(() => {
    getCurrentMixerProfile().then((mixerProfile) => {
      setMixerProfileInBackend(mixerProfile)
    })
  }, 5000)

  return () => {
    if (mixerProfileListenerIntervalId) {
      clearInterval(mixerProfileListenerIntervalId)
    }
  }
}

export default definePlugin(() => {
  console.log('[decky-virtual-surround-sound:index] Plugin initializing.')

  const unregisterCurrentProfileListener = currentProfileListener()

  return {
    // The name shown in various decky menus
    name: 'Virtual Surround Sound',
    // The element displayed at the top of your plugin's menu
    titleView: <div>Virtual Surround Sound</div>,
    // Preserve the plugin's state while the QAM is closed
    alwaysRender: true,
    // The content of your plugin's menu
    content: <QuickAccessMenuRouter />,
    // The icon displayed in the plugin list
    icon: <MdSurroundSound />,
    // The function triggered when your plugin unloads
    onDismount() {
      console.log('[decky-virtual-surround-sound:index] Unloading background profile listener.')
      if (unregisterCurrentProfileListener) unregisterCurrentProfileListener()
    },
  }
})
