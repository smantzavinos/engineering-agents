#!/usr/bin/env node

import crypto from 'node:crypto';
import fs from 'node:fs/promises';
import path from 'node:path';
import process from 'node:process';

class ExitError extends Error {
  constructor(message, exitCode) {
    super(message);
    this.exitCode = exitCode;
  }
}

function usage() {
  return 'Usage: build-managed-package-install-state.mjs --declarations <path> [--generated-at <iso-8601>]';
}

function parseArgs(argv) {
  const args = argv.slice(2);
  let declarationsPath;
  let generatedAt;

  for (let index = 0; index < args.length; index += 1) {
    const arg = args[index];

    if (arg === '--declarations') {
      declarationsPath = args[index + 1];
      index += 1;
      continue;
    }

    if (arg === '--generated-at') {
      generatedAt = args[index + 1];
      index += 1;
      continue;
    }

    throw new ExitError(`${usage()}\nUnknown argument: ${arg}`, 2);
  }

  if (!declarationsPath) {
    throw new ExitError(usage(), 2);
  }

  const normalizedGeneratedAt = generatedAt ?? new Date().toISOString();
  if (Number.isNaN(Date.parse(normalizedGeneratedAt))) {
    throw new ExitError(`invalid --generated-at timestamp: ${normalizedGeneratedAt}`, 2);
  }

  return {
    declarationsPath: path.resolve(declarationsPath),
    generatedAt: normalizedGeneratedAt,
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

function normalizeSourceSpec(source) {
  return JSON.stringify({
    type: source.type,
    spec: source.spec,
  });
}

function buildMaterializedKey(source) {
  const digest = crypto
    .createHash('sha256')
    .update(normalizeSourceSpec(source))
    .digest('hex')
    .slice(0, 16);

  return `src-${digest}`;
}

function looksLikeCommitRef(fragment) {
  return /^[0-9a-f]{7,40}$/iu.test(fragment);
}

function looksLikeTagRef(fragment) {
  return /^(?:v)?\d+(?:\.\d+){1,3}(?:[-+][0-9A-Za-z.-]+)?$/u.test(fragment);
}

function inferPinnedRefType(fragment) {
  if (looksLikeCommitRef(fragment)) {
    return 'commit';
  }

  if (fragment.startsWith('semver:')) {
    return 'semver';
  }

  return 'tag';
}

function parseGitRef(spec) {
  const fragmentIndex = spec.indexOf('#');
  if (fragmentIndex === -1 || fragmentIndex === spec.length - 1) {
    return { kind: 'default', value: null };
  }

  const fragment = spec.slice(fragmentIndex + 1);
  if (looksLikeCommitRef(fragment) || fragment.startsWith('semver:') || looksLikeTagRef(fragment)) {
    return {
      kind: 'pinned',
      value: fragment,
      refType: inferPinnedRefType(fragment),
    };
  }

  return { kind: 'branch', value: fragment };
}

function validateSourceShape(source, packageId) {
  if (!isPlainObject(source)) {
    throw new ExitError(`malformed declaration contract: source block required for ${packageId}`, 3);
  }

  for (const field of ['type', 'spec']) {
    if (typeof source[field] !== 'string' || source[field].length === 0) {
      throw new ExitError(`malformed declaration contract: source.${field} required for ${packageId}`, 3);
    }
  }

  if (source.type === 'local') {
    return;
  }

  for (const field of ['installSpec', 'packageName', 'materializedPath']) {
    if (typeof source[field] !== 'string' || source[field].length === 0) {
      throw new ExitError(`malformed declaration contract: source.${field} required for ${packageId}`, 3);
    }
  }
}

async function loadInstalledPackageVersion(materializedPath) {
  const manifest = await readJson(path.join(materializedPath, 'package.json'), {
    exitCode: 2,
    label: 'materialized package manifest',
  });

  if (typeof manifest.version !== 'string' || manifest.version.length === 0) {
    throw new ExitError(`materialized package manifest missing version: ${materializedPath}`, 3);
  }

  return manifest.version;
}

async function loadInstalledGitCommit(materializedPath) {
  const metadata = await readJson(path.join(materializedPath, '.pi-managed-install.json'), {
    exitCode: 2,
    label: 'git install metadata',
  });

  if (!isPlainObject(metadata) || metadata.schemaVersion !== 1) {
    throw new ExitError(`malformed git install metadata: ${materializedPath}`, 3);
  }

  if (typeof metadata.installedCommit !== 'string' || metadata.installedCommit.length === 0) {
    throw new ExitError(`git install metadata missing installedCommit: ${materializedPath}`, 3);
  }

  return metadata.installedCommit;
}

async function buildInstallState({ declarationsPath, generatedAt }) {
  const declarationsDir = path.dirname(declarationsPath);
  const declarations = await readJson(declarationsPath, {
    exitCode: 2,
    label: 'declarations file',
  });

  if (!isPlainObject(declarations) || !Array.isArray(declarations.packages)) {
    throw new ExitError('malformed declaration contract: top-level packages array is required', 3);
  }

  const groupedSources = new Map();

  const sortedDeclarations = [...declarations.packages].sort((left, right) => {
    const leftId = left?.packageId ?? '';
    const rightId = right?.packageId ?? '';
    return leftId.localeCompare(rightId);
  });

  for (const declaration of sortedDeclarations) {
    if (!isPlainObject(declaration)) {
      throw new ExitError('malformed declaration contract: package declarations must be objects', 3);
    }

    if (typeof declaration.packageId !== 'string' || declaration.packageId.length === 0) {
      throw new ExitError('malformed declaration contract: packageId must be a non-empty string', 3);
    }

    validateSourceShape(declaration.source, declaration.packageId);
    if (declaration.source.type === 'local') {
      continue;
    }

    const materializedPath = path.resolve(declarationsDir, declaration.source.materializedPath);
    const materializedKey = buildMaterializedKey(declaration.source);
    const sourceKey = materializedKey;
    const gitRef = declaration.source.type === 'git'
      ? parseGitRef(declaration.source.installSpec ?? declaration.source.spec)
      : null;

    let grouped = groupedSources.get(sourceKey);
    if (!grouped) {
      grouped = {
        sourceKey,
        packageIds: [],
        materializedPath,
        materializedKey,
        source: {
          type: declaration.source.type,
          spec: declaration.source.spec,
          installSpec: declaration.source.installSpec,
          packageName: declaration.source.packageName,
        },
      };

      if (declaration.source.type === 'npm') {
        grouped.installedVersion = await loadInstalledPackageVersion(materializedPath);
      }

      if (declaration.source.type === 'git') {
        grouped.installedCommit = await loadInstalledGitCommit(materializedPath);
        grouped.gitRef = gitRef;
      }

      groupedSources.set(sourceKey, grouped);
    }

    grouped.packageIds.push(declaration.packageId);
  }

  const sources = Array.from(groupedSources.values())
    .map((entry) => ({
      ...entry,
      packageIds: [...entry.packageIds].sort((left, right) => left.localeCompare(right)),
    }))
    .sort((left, right) => left.sourceKey.localeCompare(right.sourceKey));

  return {
    schemaVersion: 1,
    generatedAt,
    sources,
  };
}

async function main() {
  const options = parseArgs(process.argv);
  const result = await buildInstallState(options);
  process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
}

main().catch((error) => {
  if (error instanceof ExitError) {
    process.stderr.write(`${error.message}\n`);
    process.exit(error.exitCode);
  }

  process.stderr.write(`internal install-state helper failure: ${error instanceof Error ? error.stack ?? error.message : String(error)}\n`);
  process.exit(3);
});
