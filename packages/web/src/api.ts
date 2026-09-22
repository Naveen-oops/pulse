/**
 * The single place this app talks to the backend.
 *
 * Paths are always relative: in dev the Vite proxy forwards them, in the cluster
 * the ingress does. Nothing here needs to know which one it is talking to.
 */

export interface Poll {
  id: number
  room_id: number
  question: string
  options: string[]
  is_open: boolean
  created_at: string
}

export interface Room {
  id: number
  code: string
  title: string
  created_at: string
  polls: Poll[]
}

export interface Results {
  poll_id: number
  question: string
  options: string[]
  is_open: boolean
  counts: number[]
  total_votes: number
}

export interface RoomExport {
  room_code: string
  room_title: string
  exported_at: string
  polls: Results[]
}

export interface Question {
  id: number
  room_code: string
  text: string
  vote_count: number
  is_hidden: boolean
  is_answered: boolean
  created_at: string
}

export interface QuestionExport {
  room_code: string
  exported_at: string
  questions: Question[]
}

/** An error the API reported, carrying the message meant for the audience. */
export class ApiError extends Error {
  readonly status: number

  constructor(status: number, message: string) {
    super(message)
    this.name = 'ApiError'
    this.status = status
  }
}

const POLLS = '/api/polls'
const QA = '/api/qa'

async function readErrorMessage(response: Response): Promise<string> {
  try {
    const body: unknown = await response.json()
    const detail = (body as { detail?: unknown }).detail
    if (typeof detail === 'string') return detail
    if (Array.isArray(detail)) return 'That input is not valid.'
  } catch {
    /* body was not JSON; fall through to the generic message */
  }
  return `Something went wrong (${response.status}).`
}

async function request<T>(path: string, init: RequestInit = {}): Promise<T> {
  const response = await fetch(path, {
    ...init,
    headers: { 'Content-Type': 'application/json', ...init.headers },
  })
  if (!response.ok) {
    throw new ApiError(response.status, await readErrorMessage(response))
  }
  return (await response.json()) as T
}

function presenterHeaders(token: string): HeadersInit {
  return { 'X-Presenter-Token': token }
}

export function getRoom(code: string): Promise<Room> {
  return request<Room>(`${POLLS}/rooms/${encodeURIComponent(code)}`)
}

export function getResults(pollId: number): Promise<Results> {
  return request<Results>(`${POLLS}/polls/${pollId}/results`)
}

export function castVote(
  pollId: number,
  optionIndex: number,
  deviceId: string,
): Promise<Results> {
  return request<Results>(`${POLLS}/polls/${pollId}/votes`, {
    method: 'POST',
    body: JSON.stringify({ option_index: optionIndex, device_id: deviceId }),
  })
}

export function getRoomExport(code: string): Promise<RoomExport> {
  return request<RoomExport>(`${POLLS}/rooms/${encodeURIComponent(code)}/export`)
}

export function createRoom(title: string, code: string | null, token: string): Promise<Room> {
  return request<Room>(`${POLLS}/rooms`, {
    method: 'POST',
    headers: presenterHeaders(token),
    body: JSON.stringify({ title, code: code || null }),
  })
}

export function createPoll(
  code: string,
  question: string,
  options: string[],
  token: string,
): Promise<Poll> {
  return request<Poll>(`${POLLS}/rooms/${encodeURIComponent(code)}/polls`, {
    method: 'POST',
    headers: presenterHeaders(token),
    body: JSON.stringify({ question, options, is_open: false }),
  })
}

export function setPollOpen(pollId: number, isOpen: boolean, token: string): Promise<Poll> {
  return request<Poll>(`${POLLS}/polls/${pollId}`, {
    method: 'PATCH',
    headers: presenterHeaders(token),
    body: JSON.stringify({ is_open: isOpen }),
  })
}

export function listQuestions(code: string): Promise<Question[]> {
  return request<Question[]>(`${QA}/rooms/${encodeURIComponent(code)}/questions`)
}

export function postQuestion(code: string, text: string, deviceId: string): Promise<Question> {
  return request<Question>(`${QA}/rooms/${encodeURIComponent(code)}/questions`, {
    method: 'POST',
    body: JSON.stringify({ text, device_id: deviceId }),
  })
}

export function upvoteQuestion(questionId: number, deviceId: string): Promise<Question> {
  return request<Question>(`${QA}/questions/${questionId}/votes`, {
    method: 'POST',
    body: JSON.stringify({ device_id: deviceId }),
  })
}

export function updateQuestion(
  questionId: number,
  patch: { is_hidden?: boolean; is_answered?: boolean },
  token: string,
): Promise<Question> {
  return request<Question>(`${QA}/questions/${questionId}`, {
    method: 'PATCH',
    headers: presenterHeaders(token),
    body: JSON.stringify(patch),
  })
}

export function getQuestionExport(code: string): Promise<QuestionExport> {
  return request<QuestionExport>(`${QA}/rooms/${encodeURIComponent(code)}/questions/export`)
}
