import { describe, expect, it } from 'vitest'

import {
  getDeviceId,
  getPresenterToken,
  getVotedOption,
  markVoted,
  setPresenterToken,
} from './device'

describe('getDeviceId', () => {
  it('creates an id on first use', () => {
    const id = getDeviceId()
    expect(id).toMatch(/^device-/)
  })

  it('returns the same id on later calls, so one device is one vote', () => {
    expect(getDeviceId()).toBe(getDeviceId())
  })

  it('persists the id to localStorage', () => {
    const id = getDeviceId()
    expect(localStorage.getItem('pulse.device_id')).toBe(id)
  })

  it('is long enough for the API, which requires at least 4 characters', () => {
    expect(getDeviceId().length).toBeGreaterThanOrEqual(4)
  })
})

describe('presenter token', () => {
  it('is empty until one is saved', () => {
    expect(getPresenterToken()).toBe('')
  })

  it('round-trips through localStorage', () => {
    setPresenterToken('secret-token')
    expect(getPresenterToken()).toBe('secret-token')
  })
})

describe('remembering votes', () => {
  it('reports null before voting', () => {
    expect(getVotedOption(1)).toBeNull()
  })

  it('remembers which option this device picked', () => {
    markVoted(42, 2)
    expect(getVotedOption(42)).toBe(2)
  })

  it('remembers option 0 rather than treating it as "not voted"', () => {
    markVoted(43, 0)
    expect(getVotedOption(43)).toBe(0)
  })

  it('keeps votes for different polls apart', () => {
    markVoted(1, 0)
    markVoted(2, 3)
    expect(getVotedOption(1)).toBe(0)
    expect(getVotedOption(2)).toBe(3)
  })
})
