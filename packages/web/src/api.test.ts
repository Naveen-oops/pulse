import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'

import { ApiError, castVote, createRoom, getResults, getRoom, setPollOpen } from './api'

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
})

afterEach(() => {
  vi.unstubAllGlobals()
})

describe('request paths', () => {
  it('calls relative paths so the proxy or ingress can route them', async () => {
    fetchMock.mockResolvedValue(mockResponse({ code: 'CIT22A' }))
    await getRoom('CIT22A')
    expect(fetchMock.mock.calls[0]?.[0]).toBe('/api/polls/rooms/CIT22A')
  })

  it('url-encodes the room code', async () => {
    fetchMock.mockResolvedValue(mockResponse({}))
    await getRoom('a/b')
    expect(fetchMock.mock.calls[0]?.[0]).toBe('/api/polls/rooms/a%2Fb')
  })

  it('posts a vote with the option index and device id', async () => {
    fetchMock.mockResolvedValue(mockResponse({ counts: [1] }, 201))
    await castVote(7, 2, 'device-xyz')

    const [url, init] = fetchMock.mock.calls[0] as [string, RequestInit]
    expect(url).toBe('/api/polls/polls/7/votes')
    expect(init.method).toBe('POST')
    expect(JSON.parse(String(init.body))).toEqual({
      option_index: 2,
      device_id: 'device-xyz',
    })
  })

  it('reads results without a presenter token', async () => {
    fetchMock.mockResolvedValue(mockResponse({ counts: [] }))
    await getResults(3)
    const [, init] = fetchMock.mock.calls[0] as [string, RequestInit]
    expect(init.headers).not.toHaveProperty('X-Presenter-Token')
  })
})

describe('presenter-only calls', () => {
  it('sends the presenter token when creating a room', async () => {
    fetchMock.mockResolvedValue(mockResponse({}, 201))
    await createRoom('Build Smarter', 'CIT22A', 'secret-token')

    const [, init] = fetchMock.mock.calls[0] as [string, RequestInit]
    expect(init.headers).toMatchObject({ 'X-Presenter-Token': 'secret-token' })
    expect(JSON.parse(String(init.body))).toEqual({
      title: 'Build Smarter',
      code: 'CIT22A',
    })
  })

  it('sends null rather than an empty code so the server generates one', async () => {
    fetchMock.mockResolvedValue(mockResponse({}, 201))
    await createRoom('Ad hoc', '', 'secret-token')

    const [, init] = fetchMock.mock.calls[0] as [string, RequestInit]
    expect(JSON.parse(String(init.body)).code).toBeNull()
  })

  it('patches a poll open or closed', async () => {
    fetchMock.mockResolvedValue(mockResponse({}))
    await setPollOpen(5, true, 'secret-token')

    const [url, init] = fetchMock.mock.calls[0] as [string, RequestInit]
    expect(url).toBe('/api/polls/polls/5')
    expect(init.method).toBe('PATCH')
    expect(JSON.parse(String(init.body))).toEqual({ is_open: true })
  })
})

describe('error handling', () => {
  it('surfaces the API detail message, which the audience reads', async () => {
    fetchMock.mockResolvedValue(
      mockResponse({ detail: 'You have already voted in this poll.' }, 409),
    )

    await expect(castVote(1, 0, 'device-xyz')).rejects.toThrowError(ApiError)
    await expect(castVote(1, 0, 'device-xyz')).rejects.toThrowError(
      'You have already voted in this poll.',
    )
  })

  it('carries the status code so callers can branch on 409', async () => {
    fetchMock.mockResolvedValue(mockResponse({ detail: 'This poll is closed.' }, 409))

    const error = await castVote(1, 0, 'device-xyz').catch((caught: unknown) => caught)
    expect(error).toBeInstanceOf(ApiError)
    expect((error as ApiError).status).toBe(409)
  })

  it('turns a pydantic validation array into one readable sentence', async () => {
    fetchMock.mockResolvedValue(mockResponse({ detail: [{ loc: ['body'], msg: 'too short' }] }, 422))
    await expect(getRoom('X')).rejects.toThrowError('That input is not valid.')
  })

  it('falls back to a generic message when the body is not JSON', async () => {
    fetchMock.mockResolvedValue({
      ok: false,
      status: 502,
      json: async () => {
        throw new Error('not json')
      },
    } as unknown as Response)

    await expect(getRoom('X')).rejects.toThrowError('Something went wrong (502).')
  })
})
