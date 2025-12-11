import { useState } from 'react'
import EVSOCDashboard from './EV_SOC_Dashboard'

function App() {
  const [count, setCount] = useState(0)

  return (
    <>
      <EVSOCDashboard />
    </>
  )
}

export default App
