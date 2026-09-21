import { useCallback, useEffect, useRef, useState } from 'react'

interface PollingState<T> {
  data: T | null
  error: string | null
  loading: boolean
  refresh: () => void
}

/**
 * Re-fetches on an interval. Deliberately polling rather than WebSockets — it
 * survives flaky venue wifi and reconnects by itself.
 */
export function usePolling<T>(
  fetcher: () => Promise<T>,
  intervalMs = 2000,
  enabled = true,
): PollingState<T> {
  const [data, setData] = useState<T | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [loading, setLoading] = useState(true)

  // Keep the latest fetcher without restarting the interval on every render.
  const fetcherRef = useRef(fetcher)
  fetcherRef.current = fetcher

  const load = useCallback(async () => {
    try {
      setData(await fetcherRef.current())
      setError(null)
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : 'Could not reach the server.')
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => {
    if (!enabled) {
      setLoading(false)
      return
    }
    let active = true
    const tick = () => {
      if (active) void load()
    }
    tick()
    const timer = window.setInterval(tick, intervalMs)
    return () => {
      active = false
      window.clearInterval(timer)
    }
  }, [load, intervalMs, enabled])

  return { data, error, loading, refresh: load }
}
