#!/usr/bin/env node

// Live proof-set snapshot generator.
//
// Enumerates the activated Pi agent state from the filesystem and facade
// manifests — NOT by importing Pi's module. Pi >=0.80.8 ships as a compiled
// bundle (libexec/pi) with no importable module entrypoint, so loader-based
// enumeration stopped working when the llmAgents pin moved past 0.80.7.
// Behavioral load verification (extensions actually parse/import) lives in
// the runner's `pi list` load smoke: pi hard-fails startup when any extension
// fails to load, so `pi list` exit 0 proves every facade loads.
//
// Snapshot shape is schemaVersion 2 (unchanged from the loader-based
// generator) so tests/scripts/assert-contract.sh and the static spec
// fixtures remain valid.
//
// Inputs:
//   ~/.pi/agent/settings.json      configured packages + selected theme
//   ~/.pi/agent/packages/<id>/     generated facades (package.json pi.* lists,
//                                  meta/source.json provenance)
//   ~/.pi/agent/sources/src-*      materialized source roots
//   ~/.pi/agent/managed-packages.report.json   compiler warnings
//   ~/.pi/agent/themes/*.json      local theme overrides
//
// Output: v2 snapshot JSON on stdout. Exit codes: 0 success,
// 2 environment failure, 3 internal failure.

import { execFileSync } from 'node:child_process';
import { existsSync, lstatSync, readdirSync, readFileSync, realpathSync } from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import process from 'node:process';

const EXIT_SUCCESS = 0;
const EXIT_ENVIRONMENT = 2;
const EXIT_INTERNAL = 3;
const WARNING_CODES = new Set([
  'PI_VERIFY_WARN_EXTRA_INSTALLED_PACKAGE',
  'PI_VERIFY_WARN_UNRELATED_PI_HELP_WARNING',
  'PI_VERIFY_WARN_LOCAL_THEME_OVERRIDE',
  'PI_VERIFY_WARN_NON_PROOF_RESOURCE',
  'PI_PACKAGE_WARN_STALE_ARTIFACT_PRUNED',
]);

function compareStrings(left, right) {
  return left.localeCompare(right, 'en');
}

function stableSort(values, getKey) {
  return [...values].sort((left, right) => compareStrings(getKey(left), getKey(right)));
}

function absolutePath(value) {
  if (!value) {
    return value;
  }

  try {
    return realpathSync(value);
  } catch {
    return path.resolve(value);
  }
}

function literalAbsolutePath(value) {
  if (!value) {
    return value;
  }

  return path.resolve(value);
}

function environmentFailure(message, error) {
  error.exitCode = EXIT_ENVIRONMENT;
  error.message = `${message}: ${error.message}`;
  return error;
}

function asRelativePath(rootPath, targetPath) {
  if (!rootPath || !targetPath) {
    return undefined;
  }

  const relative = path.relative(rootPath, targetPath);
  if (!relative || relative === '') {
    return './';
  }

  return relative.startsWith('.') ? relative : `./${relative.replace(/\\/g, '/')}`;
}

function facadeRelativeToSourceRelative(relativePath, sourceRoot) {
  if (relativePath?.startsWith('./_source/')) {
    return `./${relativePath.slice('./_source/'.length)}`;
  }

  if (!sourceRoot) {
    return undefined;
  }

  const packageRootGuess = path.resolve(sourceRoot, '..', '..');
  const candidate = path.resolve(packageRootGuess, relativePath ?? '');
  const relative = path.relative(sourceRoot, candidate);
  if (!relative || relative.startsWith('..')) {
    return undefined;
  }

  return relative.startsWith('.') ? relative : `./${relative.replace(/\\/g, '/')}`;
}

function readJsonFile(filePath, errorCode, label) {
  let raw;

  try {
    raw = readFileSync(filePath, 'utf8');
  } catch (error) {
    error.exitCode = errorCode;
    error.message = `${label}: ${error.message}`;
    throw error;
  }

  try {
    return JSON.parse(raw);
  } catch (error) {
    error.exitCode = EXIT_INTERNAL;
    error.message = `${label}: ${error.message}`;
    throw error;
  }
}

function parseArgs(argv) {
  let fixturePath;

  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (argument === '--fixture') {
      fixturePath = argv[index + 1];
      index += 1;
      continue;
    }

    const error = new Error(`Unsupported argument: ${argument}`);
    error.exitCode = EXIT_ENVIRONMENT;
    throw error;
  }

  if (!fixturePath) {
    const error = new Error('Missing required --fixture argument');
    error.exitCode = EXIT_ENVIRONMENT;
    throw error;
  }

  return { fixturePath: path.resolve(fixturePath) };
}

function malformedFixture(message) {
  const error = new Error(`Malformed fixture: ${message}`);
  error.exitCode = EXIT_INTERNAL;
  return error;
}

function validateFixture(fixture) {
  if (!fixture || typeof fixture !== 'object' || Array.isArray(fixture)) {
    throw malformedFixture('fixture root must be an object');
  }

  if (fixture.schemaVersion !== 2) {
    throw malformedFixture('fixture schemaVersion must be 2');
  }

  if (!Array.isArray(fixture.packages)) {
    throw malformedFixture('fixture packages must be an array');
  }

  for (const entry of fixture.packages) {
    if (!entry || typeof entry !== 'object' || typeof entry.packageId !== 'string') {
      throw malformedFixture('each fixture package must include a string packageId');
    }

    if (typeof entry.sourceManifestName !== 'string' || entry.sourceManifestName.length === 0) {
      throw malformedFixture(`fixture package ${entry.packageId} must include sourceManifestName`);
    }

    if (typeof entry.sourceSpec !== 'string' || entry.sourceSpec.length === 0) {
      throw malformedFixture(`fixture package ${entry.packageId} must include sourceSpec`);
    }

    if (Object.hasOwn(entry, 'sharedSourceKey') && (typeof entry.sharedSourceKey !== 'string' || entry.sharedSourceKey.length === 0)) {
      throw malformedFixture(`fixture package ${entry.packageId} must use a non-empty sharedSourceKey when provided`);
    }

    const expectations = entry.resourceExpectations;
    if (!expectations || typeof expectations !== 'object') {
      throw malformedFixture(`fixture package ${entry.packageId} is missing resourceExpectations`);
    }

    for (const key of ['extensions', 'skills', 'themes']) {
      if (!Array.isArray(expectations[key]) || !expectations[key].every((value) => typeof value === 'string')) {
        throw malformedFixture(`fixture package ${entry.packageId} must define ${key} as a string array`);
      }
    }
  }
}

// Best-effort Pi binary resolution for the host block. Informational only:
// the snapshot no longer imports Pi's module (see header). A wrapper's
// PI_WRAPPER_REAL_PI_BIN export is unwrapped when present.
function resolvePiBinary() {
  let piBinary;

  try {
    piBinary = realpathSync(execFileSync('which', ['pi'], { encoding: 'utf8' }).trim());
  } catch (error) {
    const notFound = new Error(`Unable to locate pi on PATH: ${error.message}`);
    notFound.exitCode = EXIT_ENVIRONMENT;
    throw notFound;
  }

  let realPiBinary = piBinary;
  try {
    const wrapperContents = readFileSync(piBinary, 'utf8');
    const match = wrapperContents.match(/^export PI_WRAPPER_REAL_PI_BIN=(?:"([^"\n]+)"|'([^'\n]+)')\s*$/m);
    const configuredPath = match?.[1] ?? match?.[2];
    if (configuredPath && path.isAbsolute(configuredPath)) {
      realPiBinary = realpathSync(configuredPath);
    }
  } catch {
    // Not a wrapper or unreadable — report the resolved PATH binary.
  }

  return realPiBinary;
}

function fallbackPackageIdForSource(source) {
  if (!source) {
    return undefined;
  }

  if (source.startsWith('./packages/')) {
    return source.slice('./packages/'.length);
  }

  if (source.includes(':')) {
    return source.slice(source.indexOf(':') + 1);
  }

  return source;
}

function readFacadeProvenance(packageRoot) {
  if (!packageRoot) {
    return null;
  }

  const metadataPath = path.join(packageRoot, 'meta', 'source.json');
  if (!existsSync(metadataPath)) {
    return null;
  }

  try {
    return readJsonFile(metadataPath, EXIT_INTERNAL, `Unable to read facade provenance metadata for ${packageRoot}`);
  } catch {
    return null;
  }
}

function normalizeResourceList(value, field, packageId) {
  if (value == null) {
    return [];
  }

  if (!Array.isArray(value) || !value.every((entry) => typeof entry === 'string' && entry.length > 0)) {
    throw malformedFixture(`facade manifest pi.${field} for ${packageId} must be an array of non-empty strings`);
  }

  return value;
}

// Enumerate every configured package's declared resources from its facade
// manifest. Each entry records the literal facade-relative path plus the
// symlink-resolved target; a null resolvedPath means the declared resource
// is missing or its _source link is broken (surfaced as a diagnostic).
function enumeratePackageResources(packageId, facadeRoot) {
  const manifestPath = path.join(facadeRoot, 'package.json');
  if (!existsSync(manifestPath)) {
    return null;
  }

  const manifest = readJsonFile(manifestPath, EXIT_INTERNAL, `Unable to read package manifest for ${packageId}`);
  const declared = manifest?.pi ?? {};

  const extensions = normalizeResourceList(declared.extensions, 'extensions', packageId);
  const skills = normalizeResourceList(declared.skills, 'skills', packageId);
  const prompts = normalizeResourceList(declared.prompts, 'prompts', packageId);
  const themes = normalizeResourceList(declared.themes, 'themes', packageId);

  return { manifest, extensions, skills, prompts, themes };
}

function resourceTargets(packageId, resourceType, declaredPaths, facadeRoot) {
  return declaredPaths.map((declaredPath) => {
    const normalized = declaredPath.startsWith('.') ? declaredPath : `./${declaredPath}`;
    const literalPath = path.resolve(facadeRoot, normalized.slice(2));
    let resolvedPath = null;
    try {
      resolvedPath = realpathSync(literalPath);
    } catch {
      resolvedPath = null;
    }

    return {
      packageId,
      resourceType,
      relativePath: normalized,
      literalPath,
      resolvedPath,
    };
  });
}

function normalizeWarning(warning) {
  const normalized = {
    code: warning.code,
    message: warning.message,
  };

  if (warning.packageId) {
    normalized.packageId = warning.packageId;
  }

  if (warning.path) {
    normalized.path = warning.path;
  }

  return normalized;
}

function mergeWarnings(...warningSets) {
  const warnings = new Map();

  for (const warningSet of warningSets) {
    for (const warning of warningSet) {
      const normalized = normalizeWarning(warning);
      const key = `${normalized.code}\u0000${normalized.packageId ?? ''}\u0000${normalized.path ?? ''}\u0000${normalized.message}`;
      warnings.set(key, normalized);
    }
  }

  return stableSort([...warnings.values()], (warning) => `${warning.code}\u0000${warning.packageId ?? ''}\u0000${warning.path ?? ''}\u0000${warning.message}`);
}

function readCompileReportWarnings(agentDir) {
  const reportPath = path.join(agentDir, 'managed-packages.report.json');
  if (!existsSync(reportPath)) {
    return [];
  }

  let report;
  try {
    report = readJsonFile(reportPath, EXIT_INTERNAL, `Unable to read managed package report at ${reportPath}`);
  } catch {
    return [];
  }

  if (!Array.isArray(report.warnings)) {
    return [];
  }

  return report.warnings.filter((warning) => warning && typeof warning.code === 'string' && typeof warning.message === 'string');
}

// Local (top-level) themes under agentDir/themes are user overrides; they
// shadow package themes by name. The loader reported these with origin
// 'top-level'; the FS enumeration discovers the same files directly.
function collectTopLevelThemes(agentDir) {
  const themesDir = path.join(agentDir, 'themes');
  if (!existsSync(themesDir)) {
    return [];
  }

  const entries = readdirSync(themesDir, { withFileTypes: true })
    .filter((entry) => entry.isFile() && entry.name.endsWith('.json'))
    .map((entry) => ({
      name: entry.name.replace(/\.json$/u, ''),
      packageId: null,
      path: absolutePath(path.join(themesDir, entry.name)),
    }));

  return stableSort(entries, (entry) => entry.name);
}

function skillNameFromRelativePath(relativePath) {
  const parentName = path.posix.basename(path.posix.dirname(relativePath));
  if (parentName && parentName !== '.' && parentName !== '/') {
    return parentName;
  }

  return relativePath;
}

function buildPackageSnapshot({ fixtureEntry, configuredPackage, resourceEnumeration }) {
  const packageId = fixtureEntry.packageId;
  const facadeRoot = configuredPackage?.installedPath ?? null;
  const sourceProvenance = configuredPackage?.sourceProvenance ?? null;
  const sourceRoot = sourceProvenance?.sourceRoot ? literalAbsolutePath(sourceProvenance.sourceRoot) : null;

  const extensionTargets = facadeRoot && resourceEnumeration
    ? resourceTargets(packageId, 'extension', resourceEnumeration.extensions, facadeRoot)
    : [];
  const skillTargets = facadeRoot && resourceEnumeration
    ? resourceTargets(packageId, 'skill', resourceEnumeration.skills, facadeRoot)
    : [];
  const themeTargets = facadeRoot && resourceEnumeration
    ? resourceTargets(packageId, 'theme', resourceEnumeration.themes, facadeRoot)
    : [];

  const extensionEntries = stableSort(
    extensionTargets.map((target) => ({
      relativePath: target.relativePath,
      sourceRelativePath: facadeRelativeToSourceRelative(target.relativePath, sourceRoot),
      path: literalAbsolutePath(target.literalPath),
      resolvedPath: target.resolvedPath ? absolutePath(target.resolvedPath) : null,
      tools: [],
      commands: [],
      flags: [],
    })),
    (entry) => `${entry.relativePath ?? ''}\u0000${entry.path}`,
  );

  const skillEntries = stableSort(
    skillTargets.map((target) => ({
      name: skillNameFromRelativePath(target.relativePath),
      relativePath: target.relativePath,
      sourceRelativePath: facadeRelativeToSourceRelative(target.relativePath, sourceRoot),
      path: literalAbsolutePath(target.literalPath),
    })),
    (entry) => `${entry.name}\u0000${entry.path}`,
  );

  const themeEntries = stableSort(
    themeTargets.map((target) => ({
      name: path.posix.basename(target.relativePath).replace(/\.json$/u, ''),
      relativePath: target.relativePath,
      sourceRelativePath: facadeRelativeToSourceRelative(target.relativePath, sourceRoot),
      path: absolutePath(target.literalPath),
    })),
    (entry) => `${entry.name}\u0000${entry.path}`,
  );

  const missingResourceDiagnostic = (resourceType, singularLabel) => (target) => {
    if (target.resolvedPath) {
      return null;
    }

    return {
      packageId,
      resourceType,
      type: 'error',
      message: `Referenced ${singularLabel} is missing or unreadable: ${target.relativePath}`,
      path: literalAbsolutePath(target.literalPath),
      relativePath: target.relativePath,
    };
  };

  const diagnostics = {
    extensions: stableSort(
      extensionTargets.map(missingResourceDiagnostic('extension', 'extension')).filter(Boolean),
      (entry) => `${entry.type}\u0000${entry.relativePath ?? ''}\u0000${entry.message}`,
    ),
    skills: stableSort(
      skillTargets.map(missingResourceDiagnostic('skill', 'skill')).filter(Boolean),
      (entry) => `${entry.type}\u0000${entry.relativePath ?? ''}\u0000${entry.message}`,
    ),
    themes: stableSort(
      themeTargets.map(missingResourceDiagnostic('theme', 'theme')).filter(Boolean),
      (entry) => `${entry.type}\u0000${entry.relativePath ?? ''}\u0000${entry.message}`,
    ),
  };

  return {
    packageId,
    configuredPackagePath: configuredPackage?.source ?? `./packages/${packageId}`,
    facadePath: facadeRoot,
    sourceRoot,
    sourceManifestName: sourceProvenance?.sourceManifestName ?? null,
    sourceProvenance,
    discovered: {
      extensions: extensionEntries,
      skills: skillEntries,
      themes: themeEntries,
    },
    diagnostics,
  };
}

function buildWarnings({ configuredPackages, proofPackageIds, selectedTheme, availableThemes, compileReportWarnings }) {
  const warnings = [];

  for (const configuredPackage of configuredPackages) {
    if (!proofPackageIds.has(configuredPackage.packageId)) {
      warnings.push(normalizeWarning({
        code: 'PI_VERIFY_WARN_EXTRA_INSTALLED_PACKAGE',
        message: `Configured package is outside the representative proof set: ${configuredPackage.packageId}`,
        packageId: configuredPackage.packageId,
        path: configuredPackage.installedPath ?? undefined,
      }));
    }
  }

  const proofThemeNames = new Set();
  for (const theme of availableThemes) {
    if (theme.packageId && proofPackageIds.has(theme.packageId)) {
      proofThemeNames.add(theme.name);
    }
  }

  if (selectedTheme && !proofThemeNames.has(selectedTheme)) {
    const matchingTheme = availableThemes.find((theme) => theme.name === selectedTheme);
    warnings.push(normalizeWarning({
      code: 'PI_VERIFY_WARN_LOCAL_THEME_OVERRIDE',
      message: `Selected theme is outside the representative proof set: ${selectedTheme}`,
      packageId: matchingTheme?.packageId,
      path: matchingTheme?.path,
    }));
  }

  return mergeWarnings(warnings, compileReportWarnings);
}

function readSettingsFile(settingsPath) {
  let raw;

  try {
    raw = readFileSync(settingsPath, 'utf8');
  } catch (error) {
    error.exitCode = EXIT_ENVIRONMENT;
    error.message = `Unable to read Pi settings: ${error.message}`;
    throw error;
  }

  try {
    return JSON.parse(raw);
  } catch (error) {
    error.exitCode = EXIT_ENVIRONMENT;
    error.message = `Unable to read Pi settings: invalid JSON at ${settingsPath}`;
    throw error;
  }
}

async function main() {
  const { fixturePath } = parseArgs(process.argv.slice(2));
  const fixture = readJsonFile(fixturePath, EXIT_ENVIRONMENT, 'Unable to read fixture');
  validateFixture(fixture);

  const agentDir = path.join(process.env.HOME ?? os.homedir(), '.pi', 'agent');
  const settingsPath = path.join(agentDir, 'settings.json');

  let settingsStat;
  try {
    settingsStat = lstatSync(settingsPath);
  } catch (error) {
    throw environmentFailure('Unable to inspect Pi settings path', error);
  }

  const settings = readSettingsFile(settingsPath);

  if (!Array.isArray(settings.packages)) {
    const error = new Error('Pi settings packages must be an array of configured package sources');
    error.exitCode = EXIT_ENVIRONMENT;
    throw error;
  }

  const configuredPackages = settings.packages.map((source) => {
    if (typeof source !== 'string' || source.length === 0) {
      const error = new Error(`Pi settings packages entries must be strings: ${JSON.stringify(source)}`);
      error.exitCode = EXIT_ENVIRONMENT;
      throw error;
    }

    const installedPath = literalAbsolutePath(path.resolve(agentDir, source));
    const manifest = existsSync(path.join(installedPath, 'package.json'))
      ? readJsonFile(path.join(installedPath, 'package.json'), EXIT_INTERNAL, `Unable to read package manifest for ${source}`)
      : undefined;

    return {
      source,
      scope: 'user',
      filtered: false,
      installedPath,
      packageId: typeof manifest?.name === 'string' && manifest.name.length > 0
        ? manifest.name
        : fallbackPackageIdForSource(source),
      sourceProvenance: readFacadeProvenance(installedPath),
    };
  });

  const normalizedConfiguredPackages = stableSort(
    configuredPackages.map((configuredPackage) => ({
      packageId: configuredPackage.packageId,
      source: configuredPackage.source,
      scope: configuredPackage.scope,
      filtered: configuredPackage.filtered,
      installedPath: configuredPackage.installedPath,
    })),
    (entry) => `${entry.packageId ?? ''}\u0000${entry.source}`,
  );

  const packageIdIndex = new Map();
  for (const configuredPackage of configuredPackages) {
    packageIdIndex.set(configuredPackage.packageId, configuredPackage);
  }

  const proofPackageIds = new Set(fixture.packages.map((entry) => entry.packageId));

  const availableThemes = [
    ...collectTopLevelThemes(agentDir),
    ...configuredPackages.flatMap((configuredPackage) => {
      const enumeration = enumeratePackageResources(configuredPackage.packageId, configuredPackage.installedPath);
      if (!enumeration) {
        return [];
      }

      return resourceTargets(configuredPackage.packageId, 'theme', enumeration.themes, configuredPackage.installedPath)
        .filter((target) => target.resolvedPath)
        .map((target) => ({
          name: path.posix.basename(target.relativePath).replace(/\.json$/u, ''),
          packageId: configuredPackage.packageId,
          path: absolutePath(target.literalPath),
        }));
    }),
  ];

  const compileReportWarnings = readCompileReportWarnings(agentDir);
  const selectedTheme = typeof settings.theme === 'string' ? settings.theme : null;

  const proofSet = fixture.packages.map((fixtureEntry) => {
    const configuredPackage = packageIdIndex.get(fixtureEntry.packageId);
    const resourceEnumeration = configuredPackage
      ? enumeratePackageResources(fixtureEntry.packageId, configuredPackage.installedPath)
      : null;

    return buildPackageSnapshot({ fixtureEntry, configuredPackage, resourceEnumeration });
  });

  const diagnostics = stableSort(
    proofSet.flatMap((entry) => [
      ...entry.diagnostics.extensions,
      ...entry.diagnostics.skills,
      ...entry.diagnostics.themes,
    ]),
    (entry) => `${entry.packageId}\u0000${entry.resourceType}\u0000${entry.message}\u0000${entry.path ?? ''}`,
  );

  let piBinary = null;
  try {
    piBinary = resolvePiBinary();
  } catch {
    piBinary = null;
  }

  const output = {
    schemaVersion: 2,
    host: {
      hostname: os.hostname(),
      cwd: absolutePath(process.cwd()),
      agentDir: absolutePath(agentDir),
      piBinary,
      snapshotMode: 'fs-manifest',
      nodeVersion: process.version,
      npmConfigPrefix: process.env.NPM_CONFIG_PREFIX ?? null,
      offline: process.env.PI_OFFLINE === '1',
    },
    generatedAt: new Date().toISOString(),
    settings: {
      path: literalAbsolutePath(settingsPath),
      isRegularFile: settingsStat.isFile(),
      isSymlink: settingsStat.isSymbolicLink(),
      theme: selectedTheme,
      configuredPackages: normalizedConfiguredPackages,
    },
    proofSet,
    diagnostics,
    secondarySmoke: {
      offline: process.env.PI_OFFLINE === '1',
      resourceEnumeration: {
        implementation: 'fs-manifest',
        configuredPackageCount: normalizedConfiguredPackages.length,
      },
      cli: {
        list: { status: 'not-run' },
        help: { status: 'not-run' },
        loadSmoke: { status: 'runner-responsibility' },
      },
    },
    warnings: buildWarnings({
      configuredPackages: normalizedConfiguredPackages,
      proofPackageIds,
      selectedTheme,
      availableThemes,
      compileReportWarnings,
    }),
  };

  for (const warning of output.warnings) {
    if (!WARNING_CODES.has(warning.code)) {
      throw malformedFixture(`unknown warning code produced: ${warning.code}`);
    }
  }

  process.stdout.write(`${JSON.stringify(output, null, 2)}\n`);
  process.exitCode = EXIT_SUCCESS;
}

main().catch((error) => {
  const exitCode = error?.exitCode ?? EXIT_INTERNAL;
  process.stderr.write(`${error?.message ?? String(error)}\n`);
  process.exitCode = exitCode;
});
