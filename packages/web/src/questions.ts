import type { Question } from './api'

/** Presenter-only: answered questions sink below the live ranking. */
export function sortQuestionsForPresenter(questions: Question[]): Question[] {
  const open = questions.filter((question) => !question.is_answered)
  const answered = questions.filter((question) => question.is_answered)
  return [...open, ...answered]
}
