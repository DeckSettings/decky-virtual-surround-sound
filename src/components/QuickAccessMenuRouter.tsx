import React, { useEffect, useState } from 'react'
import type { PluginPage } from '../interfaces'
import PluginConfigView from './views/PluginConfigView'
import AudioControlsView from './views/AudioControlsView'
import { Footer } from './elements/AuthorFooter'


const QuickAccessMenuRouter: React.FC = () => {
  const [currentPage, setCurrentPage] = useState<PluginPage>('audio_controls')
  const changePage = (page: PluginPage) => {
    console.log(`[decky-virtual-surround-sound:QuickAccessMenuRouter] Changing page to: ${page}`)
    setCurrentPage(page)
  }

  useEffect(() => {
    console.log(`[decky-virtual-surround-sound:QuickAccessMenuRouter] Current page changed to: ${currentPage}`)
  }, [currentPage])

  return (
    <div>
      {currentPage === 'plugin_config' && (
        <PluginConfigView
          onGoBack={() => changePage('audio_controls')}
        />
      )}
      {currentPage === 'audio_controls' && (
        <AudioControlsView
          onChangePage={changePage}
        />
      )}

      {/* Footer */}
      <Footer />
    </div>
  )

}

export default QuickAccessMenuRouter
