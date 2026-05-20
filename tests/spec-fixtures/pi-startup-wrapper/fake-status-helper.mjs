#!/usr/bin/env node

import fs from 'node:fs';
import process from 'node:process';

const logPath = process.env.FAKE_STATUS_HELPER_LOG;
if (logPath) {
  fs.writeFileSync(logPath, JSON.stringify({
    execPath: process.execPath,
    argv: process.argv.slice(1),
  }, null, 2));
}

const mode = process.env.FAKE_STATUS_HELPER_MODE || 'success';

if (mode === 'nonzero') {
  process.stderr.write('simulated helper failure\n');
  process.exit(3);
}

if (mode === 'malformed') {
  process.stdout.write('{"schemaVersion": 1');
  process.exit(0);
}

process.stdout.write(`${JSON.stringify({
  schemaVersion: 1,
  mode: 'startup',
  generatedAt: '2026-05-19T12:00:00.000Z',
  settings: {
    perSourceTimeoutMs: 2000,
    overallTimeoutMs: 4000,
    maxConcurrentProbes: 4,
  },
  summary: {
    total: 1,
    current: 0,
    stale: 1,
    unknown: 0,
  },
  sources: [
    {
      sourceKey: 'src-001',
      materializedKey: 'src-001',
      materializedPath: '/tmp/materialized/pi-example',
      packageIds: ['pi-example'],
      source: {
        type: 'npm',
        spec: 'pi-example@1.0.0',
        installSpec: 'pi-example@1.0.0',
        packageName: 'pi-example',
      },
      installedVersion: '1.0.0',
      latestVersion: '1.1.0',
      status: 'stale',
    },
  ],
  warnings: [
    {
      code: 'MANAGED_PACKAGE_SOURCE_STALE',
      message: 'Managed package source is stale: pi-example',
      sourceKey: 'src-001',
      packageIds: ['pi-example'],
      detail: {
        installedVersion: '1.0.0',
        latestVersion: '1.1.0',
      },
    },
  ],
}, null, 2)}\n`);
