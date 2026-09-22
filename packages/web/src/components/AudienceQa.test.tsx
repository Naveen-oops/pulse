import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'

import { AudienceQa } from './AudienceQa'

function mockResponse(body: unknown, status = 200): Response {
  return {
    ok: status >= 200 && status < 300,
    status,
    json: async () => body,
  } as Response
}

const fetchMock = vi.fn()

beforeEach(() => {
  vi.stubGlobal('fetch', fetchMock)
  fetchMock.mockReset()
  fetchMock.mockResolvedValue(mockResponse([]))
})

afterEach(() => {
  vi.unstubAllGlobals()
})

describe('AudienceQa', () => {
  it('keeps Ask disabled until the question is at least 5 characters', async () => {
    const user = userEvent.setup()
    render(<AudienceQa code="CIT22A" />)
    await waitFor(() => expect(fetchMock).toHaveBeenCalled())

    expect(screen.getByRole('button', { name: 'Ask' })).toBeDisabled()
    await user.type(screen.getByLabelText('Your question'), 'four')
    expect(screen.getByRole('button', { name: 'Ask' })).toBeDisabled()
    await user.type(screen.getByLabelText('Your question'), '!')
    expect(screen.getByRole('button', { name: 'Ask' })).toBeEnabled()
  })

  it('disables upvote on a question this device asked', async () => {
    fetchMock.mockResolvedValue(
      mockResponse([
        {
          id: 7,
          room_code: 'CIT22A',
          text: 'How does polling survive venue wifi?',
          vote_count: 0,
          is_hidden: false,
          is_answered: false,
          created_at: '2026-09-22T06:30:00+00:00',
        },
      ]),
    )
    localStorage.setItem('pulse.asked', JSON.stringify([7]))
    render(<AudienceQa code="CIT22A" />)

    const upvote = await screen.findByRole('button', { name: 'Your question, 0 upvotes' })
    expect(upvote).toBeDisabled()
  })
})
