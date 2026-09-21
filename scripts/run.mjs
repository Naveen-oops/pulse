#!/usr/bin/env node
/**
 * Thin launcher: forwards every npm script to scripts/dev.sh in a real bash.
 *
 * Why this exists: on Windows, `bash` on PATH is usually WSL's bash
 * (C:\Windows\system32\bash.exe), which cannot see the Windows toolchain, and
 * npm's default shell there is cmd.exe, which has no `bash` at all. So we
 * resolve Git Bash explicitly instead of hoping PATH is right.
 */

import { spawnSync } from 'node:child_process'
import { existsSync } from 'node:fs'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const scriptsDir = dirname(fileURLToPath(import.meta.url))
const repoRoot = resolve(scriptsDir, '..')

const WINDOWS_BASH_CANDIDATES = [
  'C:\\Program Files\\Git\\bin\\bash.exe',
  'C:\\Program Files (x86)\\Git\\bin\\bash.exe',
  join(process.env.LOCALAPPDATA ?? '', 'Programs\\Git\\bin\\bash.exe'),
  join(process.env.ProgramW6432 ?? '', 'Git\\bin\\bash.exe'),
]

function resolveBash() {
  if (process.platform !== 'win32') return '/bin/bash'

  for (const candidate of WINDOWS_BASH_CANDIDATES) {
    if (candidate && existsSync(candidate)) return candidate
  }

  console.error(
    '\n❌ Could not find Git Bash.\n' +
      '   Install Git for Windows (https://git-scm.com/download/win), then re-run.\n' +
      '   Note: the `bash` on your PATH is WSL, which cannot run these scripts.\n',
  )
  process.exit(1)
}

const result = spawnSync(resolveBash(), [join(scriptsDir, 'dev.sh'), ...process.argv.slice(2)], {
  cwd: repoRoot,
  stdio: 'inherit',
  env: process.env,
})

process.exit(result.status ?? 1)
