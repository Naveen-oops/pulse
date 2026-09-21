import { useMemo, useState } from 'react'
import { useParams } from 'react-router-dom'

import { ApiError, castVote, getResults, getRoom, type Poll, type Results } from '../api'
import { BarChart } from '../components/BarChart'
import { getDeviceId, getVotedOption, markVoted } from '../device'
import { usePolling } from '../hooks/usePolling'

export function Audience() {
  const { code = '' } = useParams<{ code: string }>()
  const { data: room, error, loading } = usePolling(() => getRoom(code), 2000, code !== '')

  if (loading && room === null) {
    return <p className="muted">Loading room {code.toUpperCase()}…</p>
  }

  if (error !== null && room === null) {
    return (
      <div className="card">
        <h1>Room {code.toUpperCase()}</h1>
        <p className="error">{error}</p>
      </div>
    )
  }

  const openPoll = room?.polls.find((poll) => poll.is_open) ?? null

  return (
    <div className="audience">
      <header className="audience__header">
        <span className="pill">{room?.code ?? code.toUpperCase()}</span>
        <h1>{room?.title ?? 'Pulse'}</h1>
      </header>

      {openPoll === null ? (
        <div className="card card--waiting">
          <p className="waiting-dot" aria-hidden="true" />
          <p>Waiting for the presenter to open a poll…</p>
        </div>
      ) : (
        // Keyed by poll id so switching polls resets the vote state.
        <AudiencePoll key={openPoll.id} poll={openPoll} />
      )}
    </div>
  )
}

function AudiencePoll({ poll }: { poll: Poll }) {
  const deviceId = useMemo(() => getDeviceId(), [])
  const [votedIndex, setVotedIndex] = useState<number | null>(() => getVotedOption(poll.id))
  const [justVoted, setJustVoted] = useState<Results | null>(null)
  const [message, setMessage] = useState<string | null>(null)
  const [sending, setSending] = useState(false)

  const hasVoted = votedIndex !== null
  const { data: live } = usePolling(() => getResults(poll.id), 2000, hasVoted)
  const results = live ?? justVoted

  async function vote(optionIndex: number) {
    setSending(true)
    setMessage(null)
    try {
      const updated = await castVote(poll.id, optionIndex, deviceId)
      markVoted(poll.id, optionIndex)
      setVotedIndex(optionIndex)
      setJustVoted(updated)
    } catch (caught) {
      if (caught instanceof ApiError && caught.status === 409) {
        // Already voted from this device, or the poll just closed.
        setMessage(caught.message)
        if (caught.message.includes('already voted')) {
          markVoted(poll.id, optionIndex)
          setVotedIndex(optionIndex)
        }
      } else {
        setMessage(caught instanceof Error ? caught.message : 'Could not send your vote.')
      }
    } finally {
      setSending(false)
    }
  }

  return (
    <section className="card">
      <h2 className="question">{poll.question}</h2>

      {hasVoted && results !== null ? (
        <>
          <BarChart results={results} highlightIndex={votedIndex} />
          <p className="muted">
            Thanks — your vote is counted. {results.total_votes}{' '}
            {results.total_votes === 1 ? 'vote' : 'votes'} so far.
          </p>
        </>
      ) : (
        <ul className="options">
          {poll.options.map((option, index) => (
            <li key={option}>
              <button
                type="button"
                className="option"
                disabled={sending}
                onClick={() => void vote(index)}
              >
                {option}
              </button>
            </li>
          ))}
        </ul>
      )}

      {message !== null && <p className="error">{message}</p>}
    </section>
  )
}
