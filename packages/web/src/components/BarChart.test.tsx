import { render, screen } from '@testing-library/react'
import { describe, expect, it } from 'vitest'

import type { Results } from '../api'
import { BarChart } from './BarChart'

function results(overrides: Partial<Results> = {}): Results {
  return {
    poll_id: 1,
    question: 'Which AI coding tool have you used?',
    options: ['None yet', 'Copilot', 'Cursor'],
    is_open: true,
    counts: [1, 2, 5],
    total_votes: 8,
    ...overrides,
  }
}

describe('BarChart', () => {
  it('renders one bar per option', () => {
    render(<BarChart results={results()} />)
    expect(screen.getAllByRole('meter')).toHaveLength(3)
  })

  it('shows each option label and its count', () => {
    render(<BarChart results={results()} />)
    expect(screen.getByText('Copilot')).toBeInTheDocument()
    // The meter carries the count, so assert that rather than matching loose text.
    expect(screen.getByLabelText('Cursor')).toHaveAttribute('aria-valuenow', '5')
    expect(screen.getByLabelText('None yet')).toHaveAttribute('aria-valuenow', '1')
  })

  it('shows the share as a percentage of total votes', () => {
    render(<BarChart results={results({ counts: [2, 2, 4], total_votes: 8 })} />)
    expect(screen.getAllByText('(25%)')).toHaveLength(2)
    expect(screen.getByText('(50%)')).toBeInTheDocument()
  })

  it('does not divide by zero when nobody has voted', () => {
    render(<BarChart results={results({ counts: [0, 0, 0], total_votes: 0 })} />)
    expect(screen.getAllByText('(0%)')).toHaveLength(3)
  })

  it('scales bar widths against the largest count', () => {
    render(<BarChart results={results({ counts: [0, 5, 10], total_votes: 15 })} />)
    const [first, second, third] = screen.getAllByRole('meter')
    expect(first).toHaveStyle({ width: '0%' })
    expect(second).toHaveStyle({ width: '50%' })
    expect(third).toHaveStyle({ width: '100%' })
  })

  it('marks the option this device voted for', () => {
    const { container } = render(<BarChart results={results()} highlightIndex={1} />)
    expect(container.querySelectorAll('.bar--mine')).toHaveLength(1)
  })

  it('marks nothing when the viewer has not voted', () => {
    const { container } = render(<BarChart results={results()} highlightIndex={null} />)
    expect(container.querySelectorAll('.bar--mine')).toHaveLength(0)
  })

  it('labels the chart with the question for screen readers', () => {
    render(<BarChart results={results()} />)
    expect(
      screen.getByLabelText('Results for: Which AI coding tool have you used?'),
    ).toBeInTheDocument()
  })
})
