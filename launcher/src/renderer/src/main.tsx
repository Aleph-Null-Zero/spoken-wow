import { createRoot } from 'react-dom/client'
import { App } from './App'
import { loadApi } from './api'
import { StoreProvider } from './store'
import './styles.css'

void loadApi().then(() => {
  createRoot(document.getElementById('root')!).render(
    <StoreProvider>
      <App />
    </StoreProvider>
  )
})
