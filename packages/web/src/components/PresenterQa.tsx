import { useState } from 'react'

import { listQuestions, updateQuestion, type Question } from '../api'
import { usePolling } from '../hooks/usePolling'
import { sortQuestionsForPresenter } from '../questions'

export function PresenterQa({ code, token }: { code: string; token: string }) {
  const { data: questions, error, refresh } = usePolling(
    () => listQuestions(code),
    2000,
    code !== '',
  )
  const [message, setMessage] = useState<string | null>(null)

  async function patch(question: Question, body: { is_hidden?: boolean; is_answered?: boolean }) {
    setMessage(null)
    try {
      await updateQuestion(question.id, body, token)
      refresh()
    } catch (caught) {
      setMessage(caught instanceof Error ? caught.message : 'Could not update that question.')
    }
  }

  const ranked = sortQuestionsForPresenter(questions ?? [])

  return (
    <aside className="present__qa">
      <h2>Questions</h2>
      {error !== null && <p className="error">{error}</p>}
      {message !== null && <p className="error">{message}</p>}
      {ranked.length === 0 ? (
        <p className="muted">Questions from the audience will show up here.</p>
      ) : (
        <ul className="qa-list">
          {ranked.map((question) => (
            <li
              key={question.id}
              className={question.is_answered ? 'qa-item qa-item--answered' : 'qa-item'}
            >
              <p>{question.text}</p>
              <p className="muted small">
                {question.vote_count} {question.vote_count === 1 ? 'upvote' : 'upvotes'}
              </p>
              <div className="row">
                <button
                  type="button"
                  className="chip"
                  onClick={() => void patch(question, { is_hidden: true })}
                  aria-label={`Hide question: ${question.text}`}
                >
                  Hide
                </button>
                {!question.is_answered && (
                  <button
                    type="button"
                    className="chip"
                    onClick={() => void patch(question, { is_answered: true })}
                    aria-label={`Mark answered: ${question.text}`}
                  >
                    Answered
                  </button>
                )}
              </div>
            </li>
          ))}
        </ul>
      )}
    </aside>
  )
}
