import type * as Preset from '@docusaurus/preset-classic'
import type { Config } from '@docusaurus/types'
import { themes as prismThemes } from 'prism-react-renderer'

// GitHub Pages serves a project site from /<repo>/, so the base URL is
// configurable. Locally it stays at the root.
const baseUrl = process.env.DOCS_BASE_URL ?? '/'
const organizationName = process.env.GITHUB_OWNER ?? 'Naveen-oops'
const projectName = 'pulse'

const config: Config = {
  title: 'Build Smarter',
  tagline: 'Ship a real app with a coding agent — and learn why each piece exists',
  favicon: 'img/favicon.svg',

  url: `https://${organizationName}.github.io`,
  baseUrl,
  organizationName,
  projectName,
  trailingSlash: false,

  // A broken link is a broken tutorial. Fail the build, do not warn.
  onBrokenLinks: 'throw',

  i18n: {
    defaultLocale: 'en',
    locales: ['en'],
  },

  markdown: {
    mermaid: true,
    hooks: {
      onBrokenMarkdownLinks: 'throw',
    },
  },
  themes: ['@docusaurus/theme-mermaid'],

  presets: [
    [
      'classic',
      {
        docs: {
          sidebarPath: './sidebars.ts',
          // The tutorial IS the site; no /docs prefix.
          routeBasePath: '/',
          editUrl: `https://github.com/${organizationName}/${projectName}/tree/main/docs-site/`,
          showLastUpdateTime: true,
        },
        blog: false,
        theme: {
          customCss: './src/css/custom.css',
        },
      } satisfies Preset.Options,
    ],
  ],

  themeConfig: {
    colorMode: {
      defaultMode: 'dark',
      respectPrefersColorScheme: true,
    },
    navbar: {
      title: 'Build Smarter',
      logo: {
        alt: 'Pulse',
        src: 'img/logo.svg',
      },
      items: [
        { type: 'docSidebar', sidebarId: 'tutorial', position: 'left', label: 'Tutorial' },
        { to: '/reference/commands', label: 'Commands', position: 'left' },
        {
          href: `https://github.com/${organizationName}/${projectName}`,
          label: 'GitHub',
          position: 'right',
        },
      ],
    },
    footer: {
      style: 'dark',
      links: [
        {
          title: 'Tutorial',
          items: [
            { label: 'Start here', to: '/' },
            { label: 'Set up your machine', to: '/setup' },
            { label: 'Build the feature live', to: '/agentic/live-build' },
          ],
        },
        {
          title: 'Concepts',
          items: [
            { label: 'Why polling, not WebSockets', to: '/concepts/polling' },
            { label: 'One vote per device', to: '/concepts/identity' },
            { label: 'GitOps', to: '/kubernetes/gitops' },
          ],
        },
        {
          title: 'Reference',
          items: [
            { label: 'Every command', to: '/reference/commands' },
            { label: 'Troubleshooting', to: '/reference/troubleshooting' },
          ],
        },
      ],
      copyright: `Built for the Build Smarter session · ${new Date().getFullYear()}`,
    },
    prism: {
      theme: prismThemes.github,
      darkTheme: prismThemes.dracula,
      additionalLanguages: ['bash', 'python', 'json', 'yaml', 'docker', 'diff'],
    },
    tableOfContents: {
      minHeadingLevel: 2,
      maxHeadingLevel: 4,
    },
  } satisfies Preset.ThemeConfig,
}

export default config
