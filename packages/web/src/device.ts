/**
 * Device identity. There is no login in Pulse — a device is identified by a random
 * id kept in localStorage, and the API enforces one vote per device per poll.
 */

const DEVICE_KEY = 'pulse.device_id'
const TOKEN_KEY = 'pulse.presenter_token'

function randomId(): string {
  if (typeof crypto !== 'undefined' && 'randomUUID' in crypto) {
    return crypto.randomUUID()
  }
  // Older mobile browsers over plain http have no randomUUID.
  return `${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 12)}`
}

export function getDeviceId(): string {
  try {
    const existing = localStorage.getItem(DEVICE_KEY)
    if (existing) return existing
    const created = `device-${randomId()}`
    localStorage.setItem(DEVICE_KEY, created)
    return created
  } catch {
    // Private browsing can block localStorage; a per-session id still works.
    return `device-${randomId()}`
  }
}

export function getPresenterToken(): string {
  try {
    return localStorage.getItem(TOKEN_KEY) ?? ''
  } catch {
    return ''
  }
}

export function setPresenterToken(token: string): void {
  try {
    localStorage.setItem(TOKEN_KEY, token)
  } catch {
    /* nothing to do: the presenter can retype it */
  }
}

/** Remembers which polls this device already voted in, for instant UI feedback. */
export function markVoted(pollId: number, optionIndex: number): void {
  try {
    localStorage.setItem(`pulse.voted.${pollId}`, String(optionIndex))
  } catch {
    /* the API is still the source of truth */
  }
}

export function getVotedOption(pollId: number): number | null {
  try {
    const stored = localStorage.getItem(`pulse.voted.${pollId}`)
    return stored === null ? null : Number(stored)
  } catch {
    return null
  }
}
