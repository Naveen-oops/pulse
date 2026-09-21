import { Navigate, Route, Routes } from 'react-router-dom'

import { Admin } from './pages/Admin'
import { Audience } from './pages/Audience'
import { Home } from './pages/Home'
import { Presenter } from './pages/Presenter'

export function App() {
  return (
    <Routes>
      <Route path="/" element={<Home />} />
      <Route path="/r/:code" element={<Audience />} />
      <Route path="/present/:code" element={<Presenter />} />
      <Route path="/admin" element={<Admin />} />
      <Route path="*" element={<Navigate to="/" replace />} />
    </Routes>
  )
}
