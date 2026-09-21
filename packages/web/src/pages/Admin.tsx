import { useState } from 'react'
import { Link } from 'react-router-dom'

import { createPoll, createRoom, getRoom, setPollOpen, type Room } from '../api'
import { getPresenterToken, setPresenterToken } from '../device'

export function Admin() {
  const [token, setToken] = useState(getPresenterToken)
  const [room, setRoom] = useState<Room | null>(null)
  const [message, setMessage] = useState<string | null>(null)

  async function run(action: () => Promise<void>) {
    setMessage(null)
    try {
      await action()
    } catch (caught) {
      setMessage(caught instanceof Error ? caught.message : 'Something went wrong.')
    }
  }

  return (
    <div className="admin">
      <h1>Admin</h1>

      <section className="card">
        <h2>Presenter token</h2>
        <div className="row">
          <input
            type="password"
            value={token}
            onChange={(event) => setToken(event.target.value)}
            placeholder="Presenter token"
            aria-label="Presenter token"
          />
          <button type="button" onClick={() => setPresenterToken(token)}>
            Save
          </button>
        </div>
      </section>

      <LoadRoom onLoad={(loaded) => setRoom(loaded)} onError={setMessage} />

      <CreateRoom
        token={token}
        onCreated={(created) => setRoom(created)}
        onError={setMessage}
      />

      {room !== null && (
        <section className="card">
          <h2>
            {room.title} <span className="pill">{room.code}</span>
          </h2>
          <p className="muted">
            <Link to={`/present/${room.code}`}>Presenter view</Link> ·{' '}
            <Link to={`/r/${room.code}`}>Audience view</Link>
          </p>

          <ul className="polls">
            {room.polls.map((poll, index) => (
              <li key={poll.id} className="polls__item">
                <div>
                  <strong>
                    {index + 1}. {poll.question}
                  </strong>
                  <p className="muted small">{poll.options.join(' · ')}</p>
                </div>
                <button
                  type="button"
                  className={poll.is_open ? 'chip chip--on' : 'chip'}
                  onClick={() =>
                    void run(async () => {
                      await setPollOpen(poll.id, !poll.is_open, token)
                      setRoom(await getRoom(room.code))
                    })
                  }
                >
                  {poll.is_open ? 'Close' : 'Open'}
                </button>
              </li>
            ))}
          </ul>

          <AddPoll
            code={room.code}
            token={token}
            onAdded={async () => setRoom(await getRoom(room.code))}
            onError={setMessage}
          />
        </section>
      )}

      {message !== null && <p className="error">{message}</p>}
    </div>
  )
}

function LoadRoom({
  onLoad,
  onError,
}: {
  onLoad: (room: Room) => void
  onError: (message: string) => void
}) {
  const [code, setCode] = useState('CIT22A')
  return (
    <section className="card">
      <h2>Open an existing room</h2>
      <form
        className="row"
        onSubmit={(event) => {
          event.preventDefault()
          getRoom(code)
            .then(onLoad)
            .catch((caught: unknown) =>
              onError(caught instanceof Error ? caught.message : 'Could not load that room.'),
            )
        }}
      >
        <input
          value={code}
          onChange={(event) => setCode(event.target.value.toUpperCase())}
          maxLength={6}
          placeholder="Room code"
          aria-label="Room code"
        />
        <button type="submit">Load</button>
      </form>
    </section>
  )
}

function CreateRoom({
  token,
  onCreated,
  onError,
}: {
  token: string
  onCreated: (room: Room) => void
  onError: (message: string) => void
}) {
  const [title, setTitle] = useState('')
  const [code, setCode] = useState('')
  return (
    <section className="card">
      <h2>Create a room</h2>
      <form
        className="row"
        onSubmit={(event) => {
          event.preventDefault()
          createRoom(title, code || null, token)
            .then(onCreated)
            .catch((caught: unknown) =>
              onError(caught instanceof Error ? caught.message : 'Could not create the room.'),
            )
        }}
      >
        <input
          value={title}
          onChange={(event) => setTitle(event.target.value)}
          placeholder="Room title"
          aria-label="Room title"
          required
        />
        <input
          value={code}
          onChange={(event) => setCode(event.target.value.toUpperCase())}
          maxLength={6}
          placeholder="Code (optional)"
          aria-label="Room code, optional"
        />
        <button type="submit" className="primary">
          Create
        </button>
      </form>
    </section>
  )
}

function AddPoll({
  code,
  token,
  onAdded,
  onError,
}: {
  code: string
  token: string
  onAdded: () => Promise<void>
  onError: (message: string) => void
}) {
  const [question, setQuestion] = useState('')
  const [optionsText, setOptionsText] = useState('')

  return (
    <form
      className="addpoll"
      onSubmit={(event) => {
        event.preventDefault()
        const options = optionsText
          .split('\n')
          .map((line) => line.trim())
          .filter((line) => line !== '')
        createPoll(code, question, options, token)
          .then(async () => {
            setQuestion('')
            setOptionsText('')
            await onAdded()
          })
          .catch((caught: unknown) =>
            onError(caught instanceof Error ? caught.message : 'Could not add the poll.'),
          )
      }}
    >
      <h3>Add a poll</h3>
      <input
        value={question}
        onChange={(event) => setQuestion(event.target.value)}
        placeholder="Question"
        aria-label="Poll question"
        required
      />
      <textarea
        value={optionsText}
        onChange={(event) => setOptionsText(event.target.value)}
        placeholder={'One option per line\nAt least two'}
        aria-label="Poll options, one per line"
        rows={4}
        required
      />
      <button type="submit" className="primary">
        Add poll
      </button>
    </form>
  )
}
