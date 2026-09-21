import { QRCodeSVG } from 'qrcode.react'
import { useState } from 'react'
import { useParams } from 'react-router-dom'

import { getResults, getRoom, setPollOpen } from '../api'
import { BarChart } from '../components/BarChart'
import { getPresenterToken, setPresenterToken } from '../device'
import { usePolling } from '../hooks/usePolling'

export function Presenter() {
  const { code = '' } = useParams<{ code: string }>()
  const [token, setToken] = useState(getPresenterToken)
  const { data: room, error } = usePolling(() => getRoom(code), 2000, code !== '')

  const openPoll = room?.polls.find((poll) => poll.is_open) ?? null
  const { data: results } = usePolling(
    () => getResults(openPoll?.id ?? 0),
    2000,
    openPoll !== null,
  )

  const audienceUrl = `${window.location.origin}/r/${code.toUpperCase()}`

  if (token === '') {
    return <TokenGate onSave={setToken} />
  }

  async function toggle(pollId: number, isOpen: boolean) {
    await setPollOpen(pollId, isOpen, token)
  }

  return (
    <div className="present">
      <aside className="present__join">
        <p className="present__joinlabel">Join at</p>
        <p className="present__host">{window.location.host}</p>
        <p className="present__code">{room?.code ?? code.toUpperCase()}</p>
        <div className="present__qr">
          <QRCodeSVG value={audienceUrl} size={220} level="M" includeMargin />
        </div>
        <p className="muted small">{audienceUrl}</p>
      </aside>

      <main className="present__stage">
        {error !== null && <p className="error">{error}</p>}
        <h1 className="present__title">{room?.title ?? 'Pulse'}</h1>

        {openPoll === null || results === null ? (
          <p className="muted large">Open a poll to start.</p>
        ) : (
          <>
            <h2 className="present__question">{openPoll.question}</h2>
            <BarChart results={results} />
            <p className="present__total">
              {results.total_votes} {results.total_votes === 1 ? 'vote' : 'votes'}
            </p>
          </>
        )}

        <div className="present__controls">
          {(room?.polls ?? []).map((poll, index) => (
            <button
              key={poll.id}
              type="button"
              className={poll.is_open ? 'chip chip--on' : 'chip'}
              onClick={() => void toggle(poll.id, !poll.is_open)}
              title={poll.question}
            >
              {index + 1}. {poll.is_open ? 'Close' : 'Open'}
            </button>
          ))}
        </div>
      </main>
    </div>
  )
}

function TokenGate({ onSave }: { onSave: (token: string) => void }) {
  const [value, setValue] = useState('')
  return (
    <form
      className="card card--narrow"
      onSubmit={(event) => {
        event.preventDefault()
        setPresenterToken(value.trim())
        onSave(value.trim())
      }}
    >
      <h1>Presenter</h1>
      <p className="muted">This screen is for the stage. Enter the presenter token.</p>
      <input
        type="password"
        value={value}
        onChange={(event) => setValue(event.target.value)}
        placeholder="Presenter token"
        aria-label="Presenter token"
      />
      <button type="submit" className="primary" disabled={value.trim() === ''}>
        Open presenter view
      </button>
    </form>
  )
}
