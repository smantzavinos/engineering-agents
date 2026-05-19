#!/usr/bin/env node

import { spawn } from 'node:child_process';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import process from 'node:process';

class ExitError extends Error {
  constructor(message, exitCode) {
    super(message);
    this.exitCode = exitCode;
  }
}

const STARTUP_DEFAULTS = {
  perSourceTimeoutMs: 2000,
  overallTimeoutMs: 4000,
  maxConcurrentProbes: 4,
};

function usage() {
  return [
    'Usage: check-managed-package-status.mjs --manifest <path> [options]',
    '',
    'Options:',
    '  --mode <manual|startup>          Output/behavior mode (default: manual)',
    '  --format <json|text>             Output format (default: json)',
    '  --npm-bin <path>                 npm executable (default: npm)',
    '  --git-bin <path>                 git executable (default: git)',
    '  --per-source-timeout-ms <ms>     Override per-source timeout',
    '  --overall-timeout-ms <ms>        Override overall timeout',
    '  --max-concurrent-probes <count>  Override remote probe concurrency',
  ].join('\n');
}

function parsePositiveInteger(rawValue, flagName) {
  const value = Number.parseInt(rawValue, 10);
  if (!Number.isFinite(value) || value <= 0) {
    throw new ExitError(`${flagName} must be a positive integer`, 2);
  }
  return value;
}

function parseArgs(argv) {
  const args = argv.slice(2);
  const options = {
    mode: 'manual',
    format: 'json',
    npmBin: process.env.PI_MANAGED_PACKAGE_STATUS_NPM_BIN || 'npm',
    gitBin: process.env.PI_MANAGED_PACKAGE_STATUS_GIT_BIN || 'git',
    manifestPath: process.env.PI_MANAGED_PACKAGE_INSTALL_STATE_PATH,
    perSourceTimeoutMs: null,
    overallTimeoutMs: null,
    maxConcurrentProbes: null,
  };

  for (let index = 0; index < args.length; index += 1) {
    const arg = args[index];
    const value = args[index + 1];

    switch (arg) {
      case '--manifest':
        options.manifestPath = value;
        index += 1;
        break;
      case '--mode':
        options.mode = value;
        index += 1;
        break;
      case '--format':
        options.format = value;
        index += 1;
        break;
      case '--npm-bin':
        options.npmBin = value;
        index += 1;
        break;
      case '--git-bin':
        options.gitBin = value;
        index += 1;
        break;
      case '--per-source-timeout-ms':
        options.perSourceTimeoutMs = parsePositiveInteger(value, '--per-source-timeout-ms');
        index += 1;
        break;
      case '--overall-timeout-ms':
        options.overallTimeoutMs = parsePositiveInteger(value, '--overall-timeout-ms');
        index += 1;
        break;
      case '--max-concurrent-probes':
        options.maxConcurrentProbes = parsePositiveInteger(value, '--max-concurrent-probes');
        index += 1;
        break;
      case '--help':
      case '-h':
        process.stdout.write(`${usage()}\n`);
        process.exit(0);
        break;
      default:
        throw new ExitError(`${usage()}\nUnknown argument: ${arg}`, 2);
    }
  }

  if (!options.manifestPath) {
    throw new ExitError(`${usage()}\n--manifest is required`, 2);
  }

  if (!['manual', 'startup'].includes(options.mode)) {
    throw new ExitError(`unsupported mode: ${options.mode}`, 2);
  }

  if (!['json', 'text'].includes(options.format)) {
    throw new ExitError(`unsupported format: ${options.format}`, 2);
  }

  const defaults = options.mode === 'startup'
    ? STARTUP_DEFAULTS
    : { perSourceTimeoutMs: null, overallTimeoutMs: null, maxConcurrentProbes: 4 };

  return {
    ...options,
    manifestPath: path.resolve(options.manifestPath),
    settings: {
      perSourceTimeoutMs: options.perSourceTimeoutMs ?? defaults.perSourceTimeoutMs,
      overallTimeoutMs: options.overallTimeoutMs ?? defaults.overallTimeoutMs,
      maxConcurrentProbes: options.maxConcurrentProbes ?? defaults.maxConcurrentProbes,
    },
  };
}

async function readJson(filePath, { exitCode, label }) {
  let raw;

  try {
    raw = await fs.readFile(filePath, 'utf8');
  } catch (error) {
    if (error && error.code === 'ENOENT') {
      throw new ExitError(`${label} does not exist: ${filePath}`, exitCode);
    }

    if (error && error.code === 'EACCES') {
      throw new ExitError(`${label} is not readable: ${filePath}`, exitCode);
    }

    throw error;
  }

  try {
    return JSON.parse(raw);
  } catch {
    throw new ExitError(`${label} is not valid JSON: ${filePath}`, exitCode);
  }
}

function isPlainObject(value) {
  return Boolean(value) && typeof value === 'object' && !Array.isArray(value);
}

function validatePackageIds(packageIds, sourceKey) {
  if (!Array.isArray(packageIds) || packageIds.length === 0) {
    throw new ExitError(`malformed install-state contract: packageIds[] required for ${sourceKey}`, 3);
  }

  for (const packageId of packageIds) {
    if (typeof packageId !== 'string' || packageId.length === 0) {
      throw new ExitError(`malformed install-state contract: packageIds[] must contain non-empty strings for ${sourceKey}`, 3);
    }
  }

  return [...packageIds].sort((left, right) => left.localeCompare(right));
}

function looksLikeCommitRef(fragment) {
  return typeof fragment === 'string' && /^[0-9a-f]{7,40}$/iu.test(fragment);
}

function inferPinnedGitRefType(gitRef) {
  if (!isPlainObject(gitRef) || typeof gitRef.value !== 'string' || gitRef.value.length === 0) {
    return null;
  }

  if (gitRef.refType === 'commit' || gitRef.refType === 'tag' || gitRef.refType === 'semver') {
    return gitRef.refType;
  }

  if (looksLikeCommitRef(gitRef.value)) {
    return 'commit';
  }

  if (gitRef.value.startsWith('semver:')) {
    return 'semver';
  }

  return 'tag';
}

function validateSourceContract(entry) {
  if (!isPlainObject(entry)) {
    throw new ExitError('malformed install-state contract: sources[] entries must be objects', 3);
  }

  if (typeof entry.sourceKey !== 'string' || entry.sourceKey.length === 0) {
    throw new ExitError('malformed install-state contract: sourceKey is required', 3);
  }

  if (typeof entry.materializedKey !== 'string' || entry.materializedKey.length === 0) {
    throw new ExitError(`malformed install-state contract: materializedKey required for ${entry.sourceKey}`, 3);
  }

  if (typeof entry.materializedPath !== 'string' || entry.materializedPath.length === 0) {
    throw new ExitError(`malformed install-state contract: materializedPath required for ${entry.sourceKey}`, 3);
  }

  const packageIds = validatePackageIds(entry.packageIds, entry.sourceKey);

  if (!isPlainObject(entry.source)) {
    throw new ExitError(`malformed install-state contract: source object required for ${entry.sourceKey}`, 3);
  }

  for (const field of ['type', 'spec', 'installSpec', 'packageName']) {
    if (typeof entry.source[field] !== 'string' || entry.source[field].length === 0) {
      throw new ExitError(`malformed install-state contract: source.${field} required for ${entry.sourceKey}`, 3);
    }
  }

  if (!['npm', 'git'].includes(entry.source.type)) {
    throw new ExitError(`malformed install-state contract: unsupported source.type ${entry.source.type} for ${entry.sourceKey}`, 3);
  }

  if (entry.source.type === 'npm') {
    if (typeof entry.installedVersion !== 'string' || entry.installedVersion.length === 0) {
      throw new ExitError(`malformed install-state contract: installedVersion required for ${entry.sourceKey}`, 3);
    }
  }

  if (entry.source.type === 'git') {
    if (typeof entry.installedCommit !== 'string' || entry.installedCommit.length === 0) {
      throw new ExitError(`malformed install-state contract: installedCommit required for ${entry.sourceKey}`, 3);
    }

    if (!isPlainObject(entry.gitRef)) {
      throw new ExitError(`malformed install-state contract: gitRef required for ${entry.sourceKey}`, 3);
    }

    if (!['default', 'branch', 'pinned'].includes(entry.gitRef.kind)) {
      throw new ExitError(`malformed install-state contract: unsupported gitRef.kind for ${entry.sourceKey}`, 3);
    }

    if (entry.gitRef.kind === 'branch' && (typeof entry.gitRef.value !== 'string' || entry.gitRef.value.length === 0)) {
      throw new ExitError(`malformed install-state contract: gitRef.value required for branch source ${entry.sourceKey}`, 3);
    }

    if (entry.gitRef.kind === 'pinned') {
      if (typeof entry.gitRef.value !== 'string' || entry.gitRef.value.length === 0) {
        throw new ExitError(`malformed install-state contract: gitRef.value required for pinned source ${entry.sourceKey}`, 3);
      }

      const pinnedRefType = inferPinnedGitRefType(entry.gitRef);
      if (pinnedRefType == null) {
        throw new ExitError(`malformed install-state contract: unsupported gitRef.refType for ${entry.sourceKey}`, 3);
      }
    }
  }

  return {
    ...entry,
    packageIds,
    gitRef: entry.source.type === 'git' && entry.gitRef.kind === 'pinned'
      ? {
        ...entry.gitRef,
        refType: inferPinnedGitRefType(entry.gitRef),
      }
      : entry.gitRef,
  };
}

function normalizeGitRemoteUrl(spec) {
  const [repoSpec] = spec.split('#', 1);

  if (repoSpec.startsWith('github:')) {
    return `https://github.com/${repoSpec.slice('github:'.length)}.git`;
  }

  if (repoSpec.startsWith('git+https://') || repoSpec.startsWith('git+http://')) {
    return repoSpec.replace(/^git\+/, '');
  }

  if (/^(https?:\/\/|git:\/\/|ssh:\/\/|git@)/.test(repoSpec)) {
    return repoSpec;
  }

  throw new ExitError(`unsupported git remote spec: ${spec}`, 2);
}

function classifyFailure(stderr, fallbackCode) {
  const text = stderr.trim();
  const lower = text.toLowerCase();

  if (
    lower.includes('authentication failed')
    || lower.includes('could not read username')
    || lower.includes('permission denied')
    || lower.includes('terminal prompts disabled')
    || lower.includes('access denied')
  ) {
    return { reasonCode: 'AUTH_REQUIRED', reason: text || 'authentication is required to inspect the remote source' };
  }

  if (
    lower.includes('could not resolve host')
    || lower.includes('network is unreachable')
    || lower.includes('name or service not known')
    || lower.includes('temporary failure in name resolution')
    || lower.includes('eai_again')
    || lower.includes('offline')
  ) {
    return { reasonCode: 'OFFLINE', reason: text || 'network access is unavailable for the remote source lookup' };
  }

  return {
    reasonCode: fallbackCode,
    reason: text || 'remote lookup failed',
  };
}

function runCommand(command, args, { timeoutMs = null } = {}) {
  return new Promise((resolve, reject) => {
    const controller = new AbortController();
    const child = spawn(command, args, {
      stdio: ['ignore', 'pipe', 'pipe'],
      signal: controller.signal,
    });

    let stdout = '';
    let stderr = '';
    let timedOut = false;
    let timeoutHandle = null;

    child.stdout.on('data', (chunk) => {
      stdout += chunk.toString();
    });

    child.stderr.on('data', (chunk) => {
      stderr += chunk.toString();
    });

    child.on('error', (error) => {
      if (timeoutHandle) {
        clearTimeout(timeoutHandle);
      }

      if (timedOut && error?.name === 'AbortError') {
        resolve({ exitCode: null, stdout, stderr, timedOut: true });
        return;
      }

      reject(error);
    });

    child.on('close', (exitCode) => {
      if (timeoutHandle) {
        clearTimeout(timeoutHandle);
      }

      resolve({ exitCode, stdout, stderr, timedOut });
    });

    if (timeoutMs != null) {
      timeoutHandle = setTimeout(() => {
        timedOut = true;
        controller.abort();
      }, timeoutMs);
    }
  });
}

function buildUnknownResult(source, detail) {
  return {
    ...source,
    status: 'unknown',
    reasonCode: detail.reasonCode,
    reason: detail.reason,
  };
}

async function classifyNpmSource(source, context) {
  const timeoutMs = context.remainingTimeout();
  if (timeoutMs === 0) {
    return buildUnknownResult(source, {
      reasonCode: 'TIMEOUT',
      reason: 'overall status budget expired before npm lookup could start',
    });
  }

  const result = await runCommand(context.options.npmBin, ['view', source.source.packageName, 'version'], { timeoutMs });
  if (result.timedOut) {
    return buildUnknownResult(source, {
      reasonCode: 'TIMEOUT',
      reason: `timed out while checking npm package ${source.source.packageName}`,
    });
  }

  if (result.exitCode !== 0) {
    return buildUnknownResult(source, classifyFailure(result.stderr, 'LOOKUP_FAILED'));
  }

  const latestVersion = result.stdout.trim();
  if (!latestVersion) {
    return buildUnknownResult(source, {
      reasonCode: 'LOOKUP_FAILED',
      reason: `npm did not return a latest version for ${source.source.packageName}`,
    });
  }

  return {
    ...source,
    status: source.installedVersion === latestVersion ? 'current' : 'stale',
    latestVersion,
  };
}

function parseLsRemoteOutput(stdout) {
  const refs = new Map();
  let defaultRef = null;
  let headCommit = null;

  for (const rawLine of stdout.split(/\r?\n/u)) {
    const line = rawLine.trim();
    if (!line) {
      continue;
    }

    if (line.startsWith('ref: ')) {
      const match = /^ref:\s+([^\t]+)\tHEAD$/u.exec(line);
      if (match) {
        defaultRef = match[1];
      }
      continue;
    }

    const parts = line.split('\t');
    if (parts.length !== 2) {
      continue;
    }

    const [commit, ref] = parts;
    refs.set(ref, commit);
    if (ref === 'HEAD') {
      headCommit = commit;
    }
  }

  return {
    refs,
    defaultRef,
    headCommit,
  };
}

function resolveDefaultTrackedGitRef(parsed) {
  const trackedRef = parsed.defaultRef;
  return {
    trackedRef,
    trackedCommit: parsed.headCommit ?? (trackedRef ? parsed.refs.get(trackedRef) : null),
    missingReason: 'remote default branch could not be resolved',
  };
}

function resolveGitTag(parsed, tagName) {
  const tagRef = `refs/tags/${tagName}`;
  return {
    tagRef,
    tagCommit: parsed.refs.get(`${tagRef}^{}`) ?? parsed.refs.get(tagRef) ?? null,
  };
}

function resolveTrackedGitRef(source, parsed) {
  if (source.gitRef.kind === 'branch') {
    const trackedRef = `refs/heads/${source.gitRef.value}`;
    const trackedCommit = parsed.refs.get(trackedRef) ?? null;
    return {
      trackedRef,
      trackedCommit,
      missingReason: `remote ref ${trackedRef} is missing`,
    };
  }

  if (source.gitRef.kind === 'pinned' && source.gitRef.refType === 'tag') {
    const tagMatch = resolveGitTag(parsed, source.gitRef.value);
    if (!tagMatch.tagCommit) {
      return {
        ...resolveDefaultTrackedGitRef(parsed),
        trackedCommit: null,
        missingReason: `remote ref ${tagMatch.tagRef} is missing`,
      };
    }

    return resolveDefaultTrackedGitRef(parsed);
  }

  return resolveDefaultTrackedGitRef(parsed);
}

async function classifyGitSource(source, context) {
  const remoteUrl = normalizeGitRemoteUrl(source.source.installSpec || source.source.spec);
  const timeoutMs = context.remainingTimeout();
  if (timeoutMs === 0) {
    return buildUnknownResult(source, {
      reasonCode: 'TIMEOUT',
      reason: 'overall status budget expired before git lookup could start',
    });
  }

  const result = await runCommand(
    context.options.gitBin,
    ['ls-remote', '--symref', remoteUrl, 'HEAD', 'refs/heads/*', 'refs/tags/*', 'refs/tags/*^{}'],
    { timeoutMs },
  );

  if (result.timedOut) {
    return buildUnknownResult(source, {
      reasonCode: 'TIMEOUT',
      reason: `timed out while checking git source ${source.source.spec}`,
    });
  }

  if (result.exitCode !== 0) {
    return buildUnknownResult(source, classifyFailure(result.stderr, 'LOOKUP_FAILED'));
  }

  const parsed = parseLsRemoteOutput(result.stdout);
  const { trackedRef, trackedCommit, missingReason } = resolveTrackedGitRef(source, parsed);

  if (!trackedCommit) {
    return buildUnknownResult(source, {
      reasonCode: 'REF_MISSING',
      reason: missingReason,
    });
  }

  return {
    ...source,
    status: source.installedCommit === trackedCommit ? 'current' : 'stale',
    remote: {
      remoteUrl,
      ref: trackedRef,
      commit: trackedCommit,
    },
  };
}

async function classifySource(source, context) {
  if (source.source.type === 'npm') {
    return classifyNpmSource(source, context);
  }

  if (source.source.type === 'git') {
    return classifyGitSource(source, context);
  }

  throw new ExitError(`malformed install-state contract: unsupported source.type ${source.source.type}`, 3);
}

async function runWithConcurrency(items, concurrency, mapper) {
  const results = new Array(items.length);
  let nextIndex = 0;

  const worker = async () => {
    while (true) {
      const currentIndex = nextIndex;
      nextIndex += 1;
      if (currentIndex >= items.length) {
        return;
      }
      results[currentIndex] = await mapper(items[currentIndex], currentIndex);
    }
  };

  const workerCount = Math.max(1, Math.min(concurrency, items.length));
  await Promise.all(Array.from({ length: workerCount }, worker));
  return results;
}

function buildWarnings(results) {
  return results
    .filter((result) => result.status !== 'current')
    .map((result) => {
      if (result.status === 'stale') {
        return {
          code: 'MANAGED_PACKAGE_SOURCE_STALE',
          message: `Managed package source is stale: ${result.packageIds.join(', ')}`,
          sourceKey: result.sourceKey,
          packageIds: result.packageIds,
          detail: result.source.type === 'npm'
            ? { installedVersion: result.installedVersion, latestVersion: result.latestVersion }
            : { installedCommit: result.installedCommit, remoteRef: result.remote?.ref ?? null, remoteCommit: result.remote?.commit ?? null },
        };
      }

      return {
        code: 'MANAGED_PACKAGE_SOURCE_UNKNOWN',
        message: `Managed package source status is unknown: ${result.packageIds.join(', ')}`,
        sourceKey: result.sourceKey,
        packageIds: result.packageIds,
        detail: {
          reasonCode: result.reasonCode,
          reason: result.reason,
        },
      };
    });
}

function buildSummary(results) {
  return results.reduce(
    (summary, result) => {
      summary.total += 1;
      summary[result.status] += 1;
      return summary;
    },
    {
      total: 0,
      current: 0,
      stale: 0,
      unknown: 0,
    },
  );
}

function formatPackageList(packageIds) {
  return packageIds.join(', ');
}

function formatSourceLine(result) {
  if (result.status === 'stale') {
    if (result.source.type === 'npm') {
      return `- ${formatPackageList(result.packageIds)} :: ${result.source.packageName} ${result.installedVersion} -> ${result.latestVersion}`;
    }

    return `- ${formatPackageList(result.packageIds)} :: ${result.source.spec} (${result.installedCommit} -> ${result.remote.commit})`;
  }

  return `- ${formatPackageList(result.packageIds)} :: ${result.source.spec} [${result.reasonCode}] ${result.reason}`;
}

function renderText(payload, manifestPath) {
  const stale = payload.sources.filter((result) => result.status === 'stale');
  const unknown = payload.sources.filter((result) => result.status === 'unknown');
  const lines = [
    'Managed Pi package status',
    `Manifest: ${manifestPath}`,
    `Mode: ${payload.mode}`,
  ];

  if (payload.settings.perSourceTimeoutMs != null || payload.settings.overallTimeoutMs != null) {
    lines.push(
      `Settings: per-source timeout=${payload.settings.perSourceTimeoutMs ?? 'none'}ms, overall timeout=${payload.settings.overallTimeoutMs ?? 'none'}ms, max concurrent probes=${payload.settings.maxConcurrentProbes}`,
    );
  } else {
    lines.push(`Settings: per-source timeout=none, overall timeout=none, max concurrent probes=${payload.settings.maxConcurrentProbes}`);
  }

  lines.push('');

  if (stale.length > 0) {
    lines.push(`Stale managed package sources (${stale.length}):`);
    for (const result of stale) {
      lines.push(formatSourceLine(result));
    }
    lines.push('');
  }

  if (unknown.length > 0) {
    lines.push(`Unknown managed package sources (${unknown.length}):`);
    for (const result of unknown) {
      lines.push(formatSourceLine(result));
    }
    lines.push('');
  }

  if (stale.length === 0 && unknown.length === 0) {
    lines.push('All managed package sources are current.');
    lines.push('');
  }

  lines.push(`Summary: ${payload.summary.current} current, ${payload.summary.stale} stale, ${payload.summary.unknown} unknown`);
  return `${lines.join(os.EOL)}${os.EOL}`;
}

async function loadSources(manifestPath) {
  const manifest = await readJson(manifestPath, {
    exitCode: 2,
    label: 'manifest file',
  });

  if (!isPlainObject(manifest) || manifest.schemaVersion !== 1 || !Array.isArray(manifest.sources)) {
    throw new ExitError('malformed install-state contract: schemaVersion 1 with sources[] is required', 3);
  }

  return [...manifest.sources]
    .map(validateSourceContract)
    .sort((left, right) => left.sourceKey.localeCompare(right.sourceKey));
}

async function buildStatusPayload(options) {
  const sources = await loadSources(options.manifestPath);
  const startedAt = Date.now();
  const deadline = options.settings.overallTimeoutMs == null ? null : startedAt + options.settings.overallTimeoutMs;

  const context = {
    options,
    remainingTimeout() {
      const perSource = options.settings.perSourceTimeoutMs;
      if (deadline == null) {
        return perSource;
      }

      const remainingOverall = deadline - Date.now();
      if (remainingOverall <= 0) {
        return 0;
      }

      if (perSource == null) {
        return remainingOverall;
      }

      return Math.min(perSource, remainingOverall);
    },
  };

  const results = await runWithConcurrency(
    sources,
    options.settings.maxConcurrentProbes,
    (source) => classifySource(source, context),
  );

  const summary = buildSummary(results);
  return {
    schemaVersion: 1,
    mode: options.mode,
    generatedAt: new Date().toISOString(),
    settings: options.settings,
    summary,
    sources: results,
    warnings: buildWarnings(results),
  };
}

async function main() {
  const options = parseArgs(process.argv);
  const payload = await buildStatusPayload(options);

  if (options.format === 'json') {
    process.stdout.write(`${JSON.stringify(payload, null, 2)}\n`);
    return;
  }

  process.stdout.write(renderText(payload, options.manifestPath));
}

main().catch((error) => {
  if (error instanceof ExitError) {
    process.stderr.write(`${error.message}\n`);
    process.exit(error.exitCode);
  }

  process.stderr.write(`internal managed-package status helper failure: ${error instanceof Error ? error.stack ?? error.message : String(error)}\n`);
  process.exit(3);
});
