import { useMemo, useState } from 'react'

import { ApiError, listQuestions, postQuestion, upvoteQuestion } from '../api'
import {
  getDeviceId,
  hasUpvotedQuestion,
  isOwnQuestion,
  markQuestionAsked,
  markQuestionUpvoted,
} from '../device'
import { usePolling } from '../hooks/usePolling'

const MAX_LENGTH = 280
const MIN_LENGTH = 5

export function AudienceQa({ code }: { code: string }) {
  const deviceId = useMemo(() => getDeviceId(), [])
  const { data: questions, error, refresh } = usePolling(
    () => listQuestions(code),
    2000,
    code !== '',
  )
  const [text, setText] = useState('')
  const [message, setMessage] = useState<string | null>(null)
  const [sending, setSending] = useState(false)

  const trimmed = text.trim()
  const canSubmit = trimmed.length >= MIN_LENGTH && trimmed.length <= MAX_LENGTH && !sending

  async function submit() {
    setSending(true)
    setMessage(null)
    try {
      const created = await postQuestion(code, trimmed, deviceId)
      markQuestionAsked(created.id)
      setText('')
      refresh()
    } catch (caught) {
      setMessage(caught instanceof Error ? caught.message : 'Could not post your question.')
    } finally {
      setSending(false)
    }
  }

  async function upvote(questionId: number) {
    setMessage(null)
    try {
      await upvoteQuestion(questionId, deviceId)
      markQuestionUpvoted(questionId)
      refresh()
    } catch (caught) {
      if (caught instanceof ApiError && caught.status === 409) {
        if (caught.message.includes('already upvoted')) {
          markQuestionUpvoted(questionId)
        }
        setMessage(caught.message)
        refresh()
      } else {
        setMessage(caught instanceof Error ? caught.message : 'Could not send your upvote.')
      }
    }
  }

  return (
    <section className="card">
      <h2>Ask a question</h2>
      <form
        onSubmit={(event) => {
          event.preventDefault()
          if (canSubmit) void submit()
        }}
      >
        <textarea
          value={text}
          onChange={(event) => setText(event.target.value)}
          maxLength={MAX_LENGTH}
          rows={3}
          placeholder="Ask the room…"
          aria-label="Your question"
        />
        <div className="row">
          <p className="muted small" aria-live="polite">
            {text.length}/{MAX_LENGTH}
          </p>
          <button type="submit" className="primary" disabled={!canSubmit}>
            Ask
          </button>
        </div>
      </form>

      {error !== null && questions === null && <p className="error">{error}</p>}
      {message !== null && <p className="error">{message}</p>}

      {questions !== null && questions.length === 0 ? (
        <p className="muted">No questions yet. Ask the first one.</p>
      ) : (
        <ul className="qa-list">
          {(questions ?? []).map((question) => {
            const mine = isOwnQuestion(question.id)
            const voted = hasUpvotedQuestion(question.id)
            return (
              <li key={question.id} className="qa-item">
                <p>
                  {question.text}
                  {mine && <span className="pill qa-item__mine">Yours</span>}
                  {question.is_answered && <span className="muted small"> Answered</span>}
                </p>
                <button
                  type="button"
                  className="chip"
                  disabled={mine || voted}
                  onClick={() => void upvote(question.id)}
                  aria-label={
                    mine
                      ? `Your question, ${question.vote_count} upvotes`
                      : voted
                        ? `Already upvoted, ${question.vote_count} upvotes`
                        : `Upvote: ${question.text}`
                  }
                >
                  ▲ {question.vote_count}
                </button>
              </li>
            )
          })}
        </ul>
      )}
    </section>
  )
}
