#!/usr/bin/env node

import fs from 'node:fs';
import fsp from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import process from 'node:process';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);

function usage() {
  return [
    'Usage: run-startup-warning-extension.mjs --extension <path> --home <path> --now <iso> [--initial-status <text>]',
  ].join('\n');
}

function parseArgs(argv) {
  const options = {
    extensionPath: null,
    home: null,
    now: null,
    initialStatus: null,
  };

  for (let index = 2; index < argv.length; index += 1) {
    const arg = argv[index];
    const value = argv[index + 1];

    switch (arg) {
      case '--extension':
        options.extensionPath = value;
        index += 1;
        break;
      case '--home':
        options.home = value;
        index += 1;
        break;
      case '--now':
        options.now = value;
        index += 1;
        break;
      case '--initial-status':
        options.initialStatus = value;
        index += 1;
        break;
      case '--help':
      case '-h':
        process.stdout.write(`${usage()}\n`);
        process.exit(0);
        break;
      default:
        throw new Error(`Unknown argument: ${arg}`);
    }
  }

  if (!options.extensionPath || !options.home || !options.now) {
    throw new Error(usage());
  }

  return options;
}

async function loadExtension(extensionPath) {
  if (!fs.existsSync(extensionPath)) {
    throw new Error(`extension does not exist: ${extensionPath}`);
  }

  const tempPath = path.join(os.tmpdir(), `startup-warning-extension-${process.pid}-${Date.now()}.cjs`);
  await fsp.copyFile(extensionPath, tempPath);

  try {
    const loaded = require(tempPath);
    return loaded && loaded.default ? loaded.default : loaded;
  } finally {
    await fsp.rm(tempPath, { force: true });
  }
}

function findSessionStartHandler(extension) {
  if (extension?.hooks && typeof extension.hooks.session_start === 'function') {
    return extension.hooks.session_start;
  }

  if (extension && typeof extension.session_start === 'function') {
    return extension.session_start;
  }

  if (typeof extension === 'function') {
    return extension;
  }

  throw new Error('extension does not expose a session_start handler');
}

function normalizeNotification(payload) {
  if (typeof payload === 'string') {
    return { level: 'info', title: null, message: payload };
  }

  if (!payload || typeof payload !== 'object') {
    return { level: 'info', title: null, message: '' };
  }

  return {
    level: typeof payload.level === 'string' ? payload.level : 'info',
    title: typeof payload.title === 'string' ? payload.title : null,
    message: typeof payload.message === 'string' ? payload.message : '',
  };
}

async function main() {
  const options = parseArgs(process.argv);
  process.env.HOME = options.home;

  const extension = await loadExtension(options.extensionPath);
  const sessionStart = findSessionStartHandler(extension);

  const notifications = [];
  const statuses = [];
  let currentStatus = options.initialStatus;

  const ctx = {
    env: process.env,
    now: options.now,
    ui: {
      notify(payload) {
        notifications.push(normalizeNotification(payload));
      },
      setStatus(id, text) {
        currentStatus = arguments.length > 1 ? (text ?? null) : (id ?? null);
        statuses.push(currentStatus);
      },
    },
  };

  await sessionStart(ctx);

  const snapshotPath = process.env.PI_MANAGED_PACKAGE_STARTUP_STATUS_PATH ?? null;
  const output = {
    notifications,
    statuses,
    finalStatus: currentStatus ?? null,
    snapshotPath,
    snapshotExistsAfter: snapshotPath ? fs.existsSync(snapshotPath) : false,
  };

  process.stdout.write(`${JSON.stringify(output, null, 2)}\n`);
}

main().catch((error) => {
  process.stderr.write(`${error instanceof Error ? error.message : String(error)}\n`);
  process.exit(1);
});
