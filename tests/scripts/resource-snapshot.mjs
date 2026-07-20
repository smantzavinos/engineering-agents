#!/usr/bin/env node

import { execFileSync } from 'node:child_process';
import { existsSync, lstatSync, readFileSync, realpathSync } from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import process from 'node:process';
import { pathToFileURL } from 'node:url';

const EXIT_SUCCESS = 0;
const EXIT_ENVIRONMENT = 2;
const EXIT_INTERNAL = 3;
const PI_MODULE_ENTRYPOINTS = [
  '@earendil-works/pi-coding-agent/dist/index.js',
  '@mariozechner/pi-coding-agent/dist/index.js',
];
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

function inspectSettingsPath(settingsPath) {
  try {
    return lstatSync(settingsPath);
  } catch (error) {
    throw environmentFailure('Unable to inspect Pi settings path', error);
  }
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

function facadeRelativeToSourceRelative(relativePath, absoluteResourcePath, sourceRoot) {
  if (relativePath?.startsWith('./_source/')) {
    return `./${relativePath.slice('./_source/'.length)}`;
  }

  const candidate = absolutePath(absoluteResourcePath);
  const normalizedSourceRoot = absolutePath(sourceRoot);
  if (!candidate || !normalizedSourceRoot) {
    return undefined;
  }

  const relative = path.relative(normalizedSourceRoot, candidate);
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

function piModuleCandidatePaths(piBinary) {
  const prefixDir = path.dirname(path.dirname(piBinary));
  return PI_MODULE_ENTRYPOINTS.map((entrypoint) => path.join(prefixDir, 'lib/node_modules', entrypoint));
}

function findPiModulePath(piBinary) {
  return piModuleCandidatePaths(piBinary).find((candidatePath) => existsSync(candidatePath));
}

function wrapperRealPiBinary(wrapperPath) {
  let wrapperContents;

  try {
    wrapperContents = readFileSync(wrapperPath, 'utf8');
  } catch {
    return undefined;
  }

  const match = wrapperContents.match(/^export PI_WRAPPER_REAL_PI_BIN=(?:"([^"\n]+)"|'([^'\n]+)')\s*$/m);
  const configuredPath = match?.[1] ?? match?.[2];
  if (!configuredPath || !path.isAbsolute(configuredPath)) {
    return undefined;
  }

  try {
    return realpathSync(configuredPath);
  } catch {
    return undefined;
  }
}

function buildPiModulePath() {
  let piBinary;

  try {
    piBinary = realpathSync(execFileSync('which', ['pi'], { encoding: 'utf8' }).trim());
  } catch (error) {
    error.exitCode = EXIT_ENVIRONMENT;
    error.message = `Unable to locate pi on PATH: ${error.message}`;
    throw error;
  }

  const directCandidatePaths = piModuleCandidatePaths(piBinary);
  let modulePath = findPiModulePath(piBinary);
  if (modulePath) {
    return {
      piBinary,
      modulePath: absolutePath(modulePath),
    };
  }

  const realPiBinary = wrapperRealPiBinary(piBinary);
  const wrapperCandidatePaths = realPiBinary ? piModuleCandidatePaths(realPiBinary) : [];
  if (realPiBinary) {
    modulePath = findPiModulePath(realPiBinary);
    if (modulePath) {
      return {
        piBinary: realPiBinary,
        modulePath: absolutePath(modulePath),
      };
    }
  }

  const candidatePaths = [...new Set([...directCandidatePaths, ...wrapperCandidatePaths])];
  const error = new Error(`Unable to locate Pi module entrypoint. Tried: ${candidatePaths.join(', ')}`);
  error.exitCode = EXIT_ENVIRONMENT;
  throw error;
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

function normalizeConfiguredPackages(configuredPackages) {
  return stableSort(
    configuredPackages.map((configuredPackage) => ({
      packageId: configuredPackage.packageId,
      source: configuredPackage.source,
      scope: configuredPackage.scope,
      filtered: configuredPackage.filtered,
      installedPath: configuredPackage.installedPath ?? null,
    })),
    (entry) => `${entry.packageId ?? ''}\u0000${entry.source}`,
  );
}

function buildConfiguredPackageIndex(configuredPackages) {
  const packageIdIndex = new Map();
  const sourceIndex = new Map();

  for (const configuredPackage of configuredPackages) {
    if (configuredPackage.packageId) {
      packageIdIndex.set(configuredPackage.packageId, configuredPackage);
    }

    sourceIndex.set(configuredPackage.source, configuredPackage);
  }

  return { packageIdIndex, sourceIndex };
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

function normalizeExtensionEntry(extension, packageRoot, sourceRoot) {
  const packageRelativePath = asRelativePath(packageRoot, absolutePath(extension.path));

  return {
    relativePath: packageRelativePath,
    sourceRelativePath: facadeRelativeToSourceRelative(packageRelativePath, extension.resolvedPath ?? extension.path, sourceRoot),
    path: absolutePath(extension.path),
    resolvedPath: absolutePath(extension.resolvedPath),
    tools: stableSort([...extension.tools.keys()], (value) => value),
    commands: stableSort([...extension.commands.keys()], (value) => value),
    flags: stableSort([...extension.flags.keys()], (value) => value),
  };
}

function normalizeSkillEntry(skill, packageRoot, sourceRoot) {
  const packageRelativePath = asRelativePath(packageRoot, absolutePath(skill.filePath));

  return {
    name: skill.name,
    relativePath: packageRelativePath,
    sourceRelativePath: facadeRelativeToSourceRelative(packageRelativePath, skill.filePath, sourceRoot),
    path: absolutePath(skill.filePath),
  };
}

function normalizeThemePathEntry(themeName, themePath, packageRoot, sourceRoot) {
  const literalThemePath = literalAbsolutePath(themePath);
  const normalizedThemePath = absolutePath(themePath);
  const packageRelativePath = asRelativePath(packageRoot, literalThemePath);

  return {
    name: themeName,
    relativePath: packageRelativePath,
    sourceRelativePath: facadeRelativeToSourceRelative(packageRelativePath, literalThemePath, sourceRoot),
    path: normalizedThemePath,
  };
}

function normalizeThemeEntry(theme, packageRoot, sourceRoot) {
  return normalizeThemePathEntry(theme.name, theme.sourcePath, packageRoot, sourceRoot);
}

function normalizeDiagnostic(resourceType, packageId, diagnostic, packageRoot) {
  const normalized = {
    packageId,
    resourceType,
    type: diagnostic.type,
    message: diagnostic.message,
  };

  if (diagnostic.path) {
    normalized.path = absolutePath(diagnostic.path);
    normalized.relativePath = asRelativePath(packageRoot, normalized.path);
  }

  if (diagnostic.collision) {
    normalized.collision = {
      resourceType: diagnostic.collision.resourceType,
      name: diagnostic.collision.name,
      winnerPath: absolutePath(diagnostic.collision.winnerPath),
      loserPath: absolutePath(diagnostic.collision.loserPath),
      winnerSource: diagnostic.collision.winnerSource,
      loserSource: diagnostic.collision.loserSource,
    };
  }

  return normalized;
}

function normalizeExtensionLoadError(packageId, error, packageRoot) {
  return {
    packageId,
    resourceType: 'extension',
    type: 'error',
    message: error.error,
    path: absolutePath(error.path),
    relativePath: asRelativePath(packageRoot, absolutePath(error.path)),
  };
}

function isSuppressedThemeOverrideCollision(diagnostic, configuredPackage, configuredPackages) {
  if (diagnostic?.type !== 'collision' || diagnostic?.collision?.resourceType !== 'theme') {
    return false;
  }

  if (!isPathWithinPackage(configuredPackage?.installedPath, diagnostic.collision?.loserPath)) {
    return false;
  }

  return !findConfiguredPackageByPath(configuredPackages, diagnostic.collision?.winnerPath);
}

function gatherPackageDiagnostics({
  packageId,
  configuredPackage,
  configuredPackages,
  extensionLoadErrors,
  extensionDiagnostics,
  skillDiagnostics,
  themeDiagnostics,
}) {
  const packageRoot = configuredPackage?.installedPath;
  const packageSource = configuredPackage?.source;

  const matchesPackagePath = (diagnosticPath) => {
    if (!packageRoot || !diagnosticPath) {
      return false;
    }

    const normalizedPath = absolutePath(diagnosticPath);
    return normalizedPath === packageRoot || normalizedPath.startsWith(`${packageRoot}${path.sep}`);
  };

  const matchesPackageDiagnostic = (diagnostic) => {
    if (matchesPackagePath(diagnostic.path)) {
      return true;
    }

    if (diagnostic.collision) {
      return diagnostic.collision.winnerSource === packageSource || diagnostic.collision.loserSource === packageSource;
    }

    return false;
  };

  return {
    extensions: stableSort(
      [
        ...extensionLoadErrors
          .filter((error) => matchesPackagePath(error.path))
          .map((error) => normalizeExtensionLoadError(packageId, error, packageRoot)),
        ...extensionDiagnostics
          .filter((diagnostic) => matchesPackageDiagnostic(diagnostic))
          .map((diagnostic) => normalizeDiagnostic('extension', packageId, diagnostic, packageRoot)),
      ],
      (entry) => `${entry.type}\u0000${entry.relativePath ?? ''}\u0000${entry.message}`,
    ),
    skills: stableSort(
      skillDiagnostics
        .filter((diagnostic) => matchesPackageDiagnostic(diagnostic))
        .map((diagnostic) => normalizeDiagnostic('skill', packageId, diagnostic, packageRoot)),
      (entry) => `${entry.type}\u0000${entry.relativePath ?? ''}\u0000${entry.message}`,
    ),
    themes: stableSort(
      themeDiagnostics
        .filter((diagnostic) => matchesPackageDiagnostic(diagnostic))
        .filter((diagnostic) => !isSuppressedThemeOverrideCollision(diagnostic, configuredPackage, configuredPackages))
        .map((diagnostic) => normalizeDiagnostic('theme', packageId, diagnostic, packageRoot)),
      (entry) => `${entry.type}\u0000${entry.relativePath ?? ''}\u0000${entry.message}`,
    ),
  };
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

function isPathWithinPackage(packageRoot, candidatePath) {
  const normalizedPackageRoot = literalAbsolutePath(packageRoot);
  const normalizedCandidate = literalAbsolutePath(candidatePath);

  if (!normalizedPackageRoot || !normalizedCandidate) {
    return false;
  }

  return normalizedCandidate === normalizedPackageRoot || normalizedCandidate.startsWith(`${normalizedPackageRoot}${path.sep}`);
}

function findConfiguredPackageByPath(configuredPackages, candidatePath) {
  return configuredPackages.find((configuredPackage) => isPathWithinPackage(configuredPackage.installedPath, candidatePath));
}

function resolveThemeConfiguredPackage(theme, sourceIndex, configuredPackages) {
  return sourceIndex.get(theme.sourceInfo?.source)
    ?? findConfiguredPackageByPath(configuredPackages, theme.sourcePath ?? theme.sourceInfo?.path);
}

function collectCollisionThemeEntries(themeDiagnostics, configuredPackage, sourceRoot) {
  return themeDiagnostics
    .filter((diagnostic) => diagnostic?.type === 'collision' && diagnostic?.collision?.resourceType === 'theme')
    .filter((diagnostic) => isPathWithinPackage(configuredPackage?.installedPath, diagnostic.collision?.loserPath))
    .map((diagnostic) => normalizeThemePathEntry(diagnostic.collision.name, diagnostic.collision.loserPath, configuredPackage?.installedPath, sourceRoot));
}

function mergeThemeEntries(...themeEntrySets) {
  const entries = new Map();

  for (const themeEntrySet of themeEntrySets) {
    for (const entry of themeEntrySet) {
      const key = `${entry.name}\u0000${entry.path}`;
      entries.set(key, entry);
    }
  }

  return stableSort([...entries.values()], (entry) => `${entry.name}\u0000${entry.path}`);
}

function collectAvailableThemes(themes, themeDiagnostics, sourceIndex, configuredPackages) {
  const directThemes = themes.map((theme) => {
    const configuredPackage = resolveThemeConfiguredPackage(theme, sourceIndex, configuredPackages);
    return {
      name: theme.name,
      packageId: configuredPackage?.packageId,
      path: absolutePath(theme.sourcePath),
    };
  });

  const collisionThemes = themeDiagnostics
    .filter((diagnostic) => diagnostic?.type === 'collision' && diagnostic?.collision?.resourceType === 'theme')
    .map((diagnostic) => {
      const configuredPackage = findConfiguredPackageByPath(configuredPackages, diagnostic.collision?.loserPath);
      return {
        name: diagnostic.collision.name,
        packageId: configuredPackage?.packageId,
        path: absolutePath(diagnostic.collision.loserPath),
      };
    })
    .filter((theme) => theme.path);

  return mergeThemeEntries(directThemes, collisionThemes);
}

function createPackageSnapshot({
  fixtureEntry,
  configuredPackage,
  sourceProvenance,
  extensionEntries,
  skillEntries,
  themeEntries,
  extensionDiagnostics,
  skillDiagnostics,
  themeDiagnostics,
}) {
  return {
    packageId: fixtureEntry.packageId,
    configuredPackagePath: configuredPackage?.source ?? `./packages/${fixtureEntry.packageId}`,
    facadePath: configuredPackage?.installedPath ?? null,
    sourceRoot: sourceProvenance?.sourceRoot ? literalAbsolutePath(sourceProvenance.sourceRoot) : null,
    sourceManifestName: sourceProvenance?.sourceManifestName ?? null,
    sourceProvenance: sourceProvenance ?? null,
    discovered: {
      extensions: extensionEntries,
      skills: skillEntries,
      themes: themeEntries,
    },
    diagnostics: {
      extensions: extensionDiagnostics,
      skills: skillDiagnostics,
      themes: themeDiagnostics,
    },
  };
}

async function main() {
  const { fixturePath } = parseArgs(process.argv.slice(2));
  const fixture = readJsonFile(fixturePath, EXIT_ENVIRONMENT, 'Unable to read fixture');
  validateFixture(fixture);

  const agentDir = path.join(process.env.HOME ?? os.homedir(), '.pi', 'agent');
  const settingsPath = path.join(agentDir, 'settings.json');
  const settingsStat = inspectSettingsPath(settingsPath);
  const { piBinary, modulePath } = buildPiModulePath();
  const piModule = await import(pathToFileURL(modulePath).href);
  const { DefaultPackageManager, DefaultResourceLoader, SettingsManager } = piModule;

  const cwd = process.cwd();
  const settingsManager = SettingsManager.create(cwd, agentDir);

  try {
    await settingsManager.reload();
  } catch (error) {
    throw environmentFailure('Unable to load Pi settings', error);
  }

  const packageManager = new DefaultPackageManager({
    cwd,
    agentDir,
    settingsManager,
  });
  const resourceLoader = new DefaultResourceLoader({
    cwd,
    agentDir,
    settingsManager,
  });

  await resourceLoader.reload();

  const extensionsResult = resourceLoader.getExtensions();
  const skillsResult = resourceLoader.getSkills();
  const themesResult = resourceLoader.getThemes();

  const configuredPackages = packageManager.listConfiguredPackages().map((entry) => {
    const installedPath = entry.installedPath ? literalAbsolutePath(entry.installedPath) : undefined;
    const manifestPath = installedPath ? path.join(installedPath, 'package.json') : undefined;
    const manifest = manifestPath && existsSync(manifestPath)
      ? readJsonFile(manifestPath, EXIT_INTERNAL, `Unable to read package manifest for ${entry.source}`)
      : undefined;
    const packageId = typeof manifest?.name === 'string' && manifest.name.length > 0
      ? manifest.name
      : fallbackPackageIdForSource(entry.source);

    return {
      ...entry,
      installedPath,
      packageId,
      sourceProvenance: readFacadeProvenance(installedPath),
    };
  });

  const normalizedConfiguredPackages = normalizeConfiguredPackages(configuredPackages);
  const { packageIdIndex, sourceIndex } = buildConfiguredPackageIndex(configuredPackages);
  const proofPackageIds = new Set(fixture.packages.map((entry) => entry.packageId));

  const availableThemes = collectAvailableThemes(themesResult.themes, themesResult.diagnostics, sourceIndex, configuredPackages);
  const compileReportWarnings = readCompileReportWarnings(agentDir);

  const proofSet = fixture.packages.map((fixtureEntry) => {
    const configuredPackage = packageIdIndex.get(fixtureEntry.packageId)
      ?? sourceIndex.get(`./packages/${fixtureEntry.packageId}`);
    const packageRoot = configuredPackage?.installedPath;
    const sourceProvenance = configuredPackage?.sourceProvenance ?? null;
    const sourceRoot = sourceProvenance?.sourceRoot ? literalAbsolutePath(sourceProvenance.sourceRoot) : null;
    const packageSource = configuredPackage?.source;

    const extensionEntries = stableSort(
      extensionsResult.extensions
        .filter((extension) => extension.sourceInfo.source === packageSource)
        .map((extension) => normalizeExtensionEntry(extension, packageRoot, sourceRoot)),
      (entry) => `${entry.relativePath ?? ''}\u0000${entry.path}`,
    );

    const skillEntries = stableSort(
      skillsResult.skills
        .filter((skill) => skill.sourceInfo.source === packageSource)
        .map((skill) => normalizeSkillEntry(skill, packageRoot, sourceRoot)),
      (entry) => `${entry.name}\u0000${entry.path}`,
    );

    const themeEntries = mergeThemeEntries(
      themesResult.themes
        .filter((theme) => resolveThemeConfiguredPackage(theme, sourceIndex, configuredPackages)?.packageId === fixtureEntry.packageId)
        .map((theme) => normalizeThemeEntry(theme, packageRoot, sourceRoot)),
      collectCollisionThemeEntries(themesResult.diagnostics, configuredPackage, sourceRoot),
    );

    const diagnostics = gatherPackageDiagnostics({
      packageId: fixtureEntry.packageId,
      configuredPackage,
      configuredPackages,
      extensionLoadErrors: extensionsResult.errors,
      extensionDiagnostics: [],
      skillDiagnostics: skillsResult.diagnostics,
      themeDiagnostics: themesResult.diagnostics,
    });

    return createPackageSnapshot({
      fixtureEntry,
      configuredPackage,
      sourceProvenance,
      extensionEntries,
      skillEntries,
      themeEntries,
      extensionDiagnostics: diagnostics.extensions,
      skillDiagnostics: diagnostics.skills,
      themeDiagnostics: diagnostics.themes,
    });
  });

  const diagnostics = stableSort(
    proofSet.flatMap((entry) => [
      ...entry.diagnostics.extensions,
      ...entry.diagnostics.skills,
      ...entry.diagnostics.themes,
    ]),
    (entry) => `${entry.packageId}\u0000${entry.resourceType}\u0000${entry.message}\u0000${entry.path ?? ''}`,
  );

  const output = {
    schemaVersion: 2,
    host: {
      hostname: os.hostname(),
      cwd: absolutePath(cwd),
      agentDir: absolutePath(agentDir),
      piBinary,
      piModulePath: modulePath,
      nodeVersion: process.version,
      npmConfigPrefix: process.env.NPM_CONFIG_PREFIX ?? null,
      offline: process.env.PI_OFFLINE === '1',
    },
    generatedAt: new Date().toISOString(),
    settings: {
      path: literalAbsolutePath(settingsPath),
      isRegularFile: settingsStat.isFile(),
      isSymlink: settingsStat.isSymbolicLink(),
      theme: settingsManager.getTheme() ?? null,
      configuredPackages: normalizedConfiguredPackages,
    },
    proofSet,
    diagnostics,
    secondarySmoke: {
      offline: process.env.PI_OFFLINE === '1',
      resourceLoader: {
        implementation: 'DefaultResourceLoader.reload()',
        configuredPackageCount: normalizedConfiguredPackages.length,
      },
      cli: {
        list: { status: 'not-run' },
        help: { status: 'not-run' },
      },
    },
    warnings: buildWarnings({
      configuredPackages: normalizedConfiguredPackages,
      proofPackageIds,
      selectedTheme: settingsManager.getTheme() ?? null,
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
