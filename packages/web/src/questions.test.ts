import { describe, expect, it } from 'vitest'

import type { Question } from './api'
import { sortQuestionsForPresenter } from './questions'

function question(overrides: Partial<Question>): Question {
  return {
    id: 1,
    room_code: 'CIT22A',
    text: 'A question',
    vote_count: 0,
    is_hidden: false,
    is_answered: false,
    created_at: '2026-09-22T06:30:00+00:00',
    ...overrides,
  }
}

describe('sortQuestionsForPresenter', () => {
  it('keeps unanswered questions above answered ones', () => {
    const answered = question({ id: 1, text: 'Answered', vote_count: 9, is_answered: true })
    const open = question({ id: 2, text: 'Still open', vote_count: 1, is_answered: false })
    expect(sortQuestionsForPresenter([answered, open]).map((item) => item.id)).toEqual([2, 1])
  })

  it('keeps API order inside each group', () => {
    const first = question({ id: 1, vote_count: 3 })
    const second = question({ id: 2, vote_count: 1 })
    const answered = question({ id: 3, is_answered: true, vote_count: 8 })
    expect(sortQuestionsForPresenter([first, second, answered]).map((item) => item.id)).toEqual([
      1, 2, 3,
    ])
  })
})
