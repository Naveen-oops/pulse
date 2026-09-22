import type { SidebarsConfig } from '@docusaurus/plugin-content-docs'

/**
 * Ordered deliberately: each section only relies on what came before it, so a
 * participant can follow top to bottom without jumping ahead.
 */
const sidebars: SidebarsConfig = {
  tutorial: [
    'index',
    'runsheet',
    {
      type: 'category',
      label: 'Get it running',
      collapsed: false,
      items: ['setup', 'tour'],
    },
    {
      type: 'category',
      label: 'Why it is built this way',
      collapsed: false,
      items: ['concepts/polling', 'concepts/identity', 'concepts/relative-paths', 'concepts/tests'],
    },
    {
      type: 'category',
      label: 'Ship it',
      collapsed: false,
      items: ['kubernetes/containers', 'kubernetes/local-cluster', 'kubernetes/gitops', 'kubernetes/ci'],
    },
    {
      type: 'category',
      label: 'Agentic engineering',
      collapsed: false,
      items: ['agentic/rules', 'agentic/spec', 'agentic/live-build', 'agentic/review'],
    },
    {
      type: 'category',
      label: 'Reference',
      collapsed: true,
      items: ['reference/commands', 'reference/troubleshooting'],
    },
  ],
}

export default sidebars
