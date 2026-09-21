import type { Results } from '../api'

interface BarChartProps {
  results: Results
  highlightIndex?: number | null
}

/** Plain CSS bars — no chart library, so nothing to fail on stage. */
export function BarChart({ results, highlightIndex = null }: BarChartProps) {
  const max = Math.max(1, ...results.counts)

  return (
    <ul className="chart" aria-label={`Results for: ${results.question}`}>
      {results.options.map((option, index) => {
        const count = results.counts[index] ?? 0
        const share = results.total_votes === 0 ? 0 : Math.round((count / results.total_votes) * 100)
        return (
          <li key={option} className={index === highlightIndex ? 'bar bar--mine' : 'bar'}>
            <div className="bar__label">
              <span className="bar__option">{option}</span>
              <span className="bar__count">
                {count} <span className="bar__share">({share}%)</span>
              </span>
            </div>
            <div className="bar__track">
              <div
                className="bar__fill"
                style={{ width: `${Math.round((count / max) * 100)}%` }}
                role="meter"
                aria-valuenow={count}
                aria-valuemin={0}
                aria-valuemax={results.total_votes}
                aria-label={option}
              />
            </div>
          </li>
        )
      })}
    </ul>
  )
}
