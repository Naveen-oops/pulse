import { useState } from 'react'
import { Link, useNavigate } from 'react-router-dom'

export function Home() {
  const [code, setCode] = useState('')
  const navigate = useNavigate()

  return (
    <div className="card card--narrow">
      <h1>Pulse</h1>
      <p className="muted">Live polls and Q&amp;A for the room you are sitting in.</p>

      <form
        className="row"
        onSubmit={(event) => {
          event.preventDefault()
          if (code.trim() !== '') navigate(`/r/${code.trim().toUpperCase()}`)
        }}
      >
        <input
          value={code}
          onChange={(event) => setCode(event.target.value.toUpperCase())}
          placeholder="Room code"
          aria-label="Room code"
          maxLength={6}
          autoCapitalize="characters"
          autoCorrect="off"
        />
        <button type="submit" className="primary" disabled={code.trim() === ''}>
          Join
        </button>
      </form>

      <p className="muted small">
        Running the session? <Link to="/admin">Admin</Link>
      </p>
    </div>
  )
}
