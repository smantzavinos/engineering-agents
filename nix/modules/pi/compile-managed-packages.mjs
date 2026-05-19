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
  return 'Usage: compile-managed-packages.mjs --declarations <path> --output-dir <path>';
}

function parseArgs(argv) {
  const args = argv.slice(2);
  let declarationsPath;
  let outputDir;

  for (let index = 0; index < args.length; index += 1) {
    const arg = args[index];

    if (arg === '--declarations') {
      declarationsPath = args[index + 1];
      index += 1;
      continue;
    }

    if (arg === '--output-dir') {
      outputDir = args[index + 1];
      index += 1;
      continue;
    }

    throw new ExitError(`${usage()}\nUnknown argument: ${arg}`, 2);
  }

  if (!declarationsPath || !outputDir) {
    throw new ExitError(usage(), 2);
  }

  return {
    declarationsPath: path.resolve(declarationsPath),
    outputDir: path.resolve(outputDir),
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
  } catch (error) {
    throw new ExitError(`${label} is not valid JSON: ${filePath}`, exitCode);
  }
}

function isPlainObject(value) {
  return Boolean(value) && typeof value === 'object' && !Array.isArray(value);
}

function ensurePathSafePackageId(packageId) {
  if (typeof packageId !== 'string' || packageId.length === 0) {
    throw new ExitError('malformed declaration contract: packageId must be a non-empty string', 3);
  }

  if (!/^[A-Za-z0-9._-]+$/.test(packageId)) {
    throw new ExitError(`malformed declaration contract: packageId must be path-safe (${packageId})`, 3);
  }
}

function normalizeRelativePath(value, { field }) {
  if (typeof value !== 'string' || value.length === 0) {
    throw new ExitError(`malformed declaration contract: ${field} entries must be non-empty strings`, 3);
  }

  const normalized = path.posix.normalize(value.replace(/\\/g, '/'));
  const withoutLeadingSlash = normalized.replace(/^\/+/, '');
  const withDotPrefix = withoutLeadingSlash.startsWith('./') ? withoutLeadingSlash : `./${withoutLeadingSlash}`;

  if (withDotPrefix === '.' || withDotPrefix.startsWith('../') || withDotPrefix.includes('/../')) {
    throw new ExitError(`malformed declaration contract: ${field} entries must stay within the source root`, 3);
  }

  return withDotPrefix;
}

function normalizeSelectionIds(values, { field, kind }) {
  if (values == null) {
    return null;
  }

  if (!Array.isArray(values)) {
    throw new ExitError(`malformed declaration contract: ${field} must be an array`, 3);
  }

  const normalized = values.map((value) => {
    if (kind === 'path') {
      return normalizeRelativePath(value, { field });
    }

    if (typeof value !== 'string' || value.length === 0) {
      throw new ExitError(`malformed declaration contract: ${field} entries must be non-empty strings`, 3);
    }

    return value;
  });

  return Array.from(new Set(normalized)).sort((left, right) => left.localeCompare(right));
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

async function ensureDirectory(directoryPath) {
  await fs.mkdir(directoryPath, { recursive: true });
}

async function ensureSymlink(linkPath, targetPath) {
  try {
    const existing = await fs.lstat(linkPath);
    if (existing.isSymbolicLink()) {
      const currentTarget = await fs.readlink(linkPath);
      const resolvedCurrentTarget = path.resolve(path.dirname(linkPath), currentTarget);
      if (resolvedCurrentTarget === targetPath) {
        return;
      }
    }
    await fs.rm(linkPath, { recursive: true, force: true });
  } catch (error) {
    if (!error || error.code !== 'ENOENT') {
      throw error;
    }
  }

  await fs.symlink(targetPath, linkPath, 'dir');
}

async function fileExists(absolutePath) {
  try {
    await fs.access(absolutePath);
    return true;
  } catch {
    return false;
  }
}

async function discoverConventionSkills(sourcePath) {
  const skillsDir = path.join(sourcePath, 'skills');
  const discovered = new Map();
  let entries = [];

  try {
    entries = await fs.readdir(skillsDir, { withFileTypes: true });
  } catch (error) {
    if (error && error.code === 'ENOENT') {
      return discovered;
    }
    throw error;
  }

  for (const entry of entries.sort((left, right) => left.name.localeCompare(right.name))) {
    if (!entry.isDirectory()) {
      continue;
    }

    const relativePath = `./skills/${entry.name}/SKILL.md`;
    const absolutePath = path.join(sourcePath, relativePath.slice(2));
    if (await fileExists(absolutePath)) {
      discovered.set(entry.name, relativePath);
    }
  }

  return discovered;
}

async function discoverConventionThemes(sourcePath) {
  const themesDir = path.join(sourcePath, 'themes');
  const discovered = new Map();
  let entries = [];

  try {
    entries = await fs.readdir(themesDir, { withFileTypes: true });
  } catch (error) {
    if (error && error.code === 'ENOENT') {
      return discovered;
    }
    throw error;
  }

  for (const entry of entries.sort((left, right) => left.name.localeCompare(right.name))) {
    if (!entry.isFile() || !entry.name.endsWith('.json')) {
      continue;
    }

    const name = entry.name.replace(/\.json$/u, '');
    discovered.set(name, `./themes/${entry.name}`);
  }

  return discovered;
}

async function discoverConventionPrompts(sourcePath) {
  const promptsDir = path.join(sourcePath, 'prompts');
  const discovered = new Map();
  let entries = [];

  try {
    entries = await fs.readdir(promptsDir, { withFileTypes: true });
  } catch (error) {
    if (error && error.code === 'ENOENT') {
      return discovered;
    }
    throw error;
  }

  for (const entry of entries.sort((left, right) => left.name.localeCompare(right.name))) {
    if (!entry.isFile()) {
      continue;
    }

    discovered.set(`./prompts/${entry.name}`, `./prompts/${entry.name}`);
  }

  return discovered;
}

function skillIdFromRelativePath(relativePath) {
  if (relativePath.endsWith('/SKILL.md')) {
    const parentName = path.posix.basename(path.posix.dirname(relativePath));
    if (parentName && parentName !== '.' && parentName !== '/') {
      return parentName;
    }
  }

  return relativePath;
}

async function walkManifestResourceFiles(sourcePath, relativePath, { resourceType, filePredicate }) {
  const absolutePath = path.join(sourcePath, relativePath.slice(2));
  let stats;

  try {
    stats = await fs.stat(absolutePath);
  } catch (error) {
    if (error && error.code === 'ENOENT') {
      throw new ExitError(`missing materialized source file referenced by manifest: ${relativePath}`, 2);
    }
    throw error;
  }

  if (stats.isFile()) {
    return [{ relativePath, absolutePath }];
  }

  if (!stats.isDirectory()) {
    throw new ExitError(`missing materialized source file referenced by manifest: ${relativePath}`, 2);
  }

  const discoveredFiles = [];
  const queue = [absolutePath];

  while (queue.length > 0) {
    const currentDir = queue.shift();
    const entries = (await fs.readdir(currentDir, { withFileTypes: true }))
      .sort((left, right) => left.name.localeCompare(right.name));

    for (const entry of entries) {
      const entryAbsolutePath = path.join(currentDir, entry.name);
      const entryRelativePath = `./${path.relative(sourcePath, entryAbsolutePath).replace(/\\/g, '/')}`;

      if (entry.isDirectory()) {
        queue.push(entryAbsolutePath);
        continue;
      }

      if (entry.isFile() && filePredicate(entryRelativePath)) {
        discoveredFiles.push({ relativePath: entryRelativePath, absolutePath: entryAbsolutePath });
      }
    }
  }

  return discoveredFiles;
}

async function discoverManifestSkills(sourcePath, manifestSkills) {
  if (manifestSkills == null) {
    return null;
  }

  const normalizedEntries = normalizeSelectionIds(manifestSkills, {
    field: 'package.json pi.skills',
    kind: 'path',
  });
  const discovered = new Map();

  for (const relativePath of normalizedEntries) {
    let files;
    try {
      files = await walkManifestResourceFiles(sourcePath, relativePath, {
        resourceType: 'skills',
        filePredicate: (entryRelativePath) => entryRelativePath.endsWith('/SKILL.md') || entryRelativePath.endsWith('SKILL.md'),
      });
    } catch (error) {
      if (error instanceof ExitError && error.exitCode === 2) {
        continue;
      }
      throw error;
    }

    for (const file of files) {
      const skillId = skillIdFromRelativePath(file.relativePath);
      discovered.set(skillId, file.relativePath);
    }
  }

  return discovered;
}

async function discoverManifestPrompts(sourcePath, manifestPrompts) {
  if (manifestPrompts == null) {
    return null;
  }

  const normalizedEntries = normalizeSelectionIds(manifestPrompts, {
    field: 'package.json pi.prompts',
    kind: 'path',
  });
  const discovered = new Map();

  for (const relativePath of normalizedEntries) {
    let files;
    try {
      files = await walkManifestResourceFiles(sourcePath, relativePath, {
        resourceType: 'prompts',
        filePredicate: () => true,
      });
    } catch (error) {
      if (error instanceof ExitError && error.exitCode === 2) {
        continue;
      }
      throw error;
    }

    for (const file of files) {
      discovered.set(file.relativePath, file.relativePath);
    }
  }

  return discovered;
}

async function discoverManifestThemes(sourcePath, manifestThemes) {
  if (manifestThemes == null) {
    return null;
  }

  const normalizedEntries = normalizeSelectionIds(manifestThemes, {
    field: 'package.json pi.themes',
    kind: 'path',
  });
  const discovered = new Map();

  for (const relativePath of normalizedEntries) {
    let files;
    try {
      files = await walkManifestResourceFiles(sourcePath, relativePath, {
        resourceType: 'themes',
        filePredicate: (entryRelativePath) => entryRelativePath.endsWith('.json'),
      });
    } catch (error) {
      if (error instanceof ExitError && error.exitCode === 2) {
        continue;
      }
      throw error;
    }

    for (const file of files) {
      const themeName = path.posix.basename(file.relativePath, '.json');
      discovered.set(themeName, file.relativePath);
    }
  }

  return discovered;
}

async function loadSourceManifest(sourcePath) {
  const manifestPath = path.join(sourcePath, 'package.json');
  const manifest = await readJson(manifestPath, {
    exitCode: 2,
    label: 'source manifest',
  });

  if (typeof manifest.name !== 'string' || manifest.name.length === 0) {
    throw new ExitError(`malformed declaration contract: source manifest missing name (${manifestPath})`, 3);
  }

  return manifest;
}

async function discoverResources(sourcePath, manifest) {
  const manifestExtensions = normalizeSelectionIds(manifest.pi?.extensions ?? [], {
    field: 'package.json pi.extensions',
    kind: 'path',
  });

  const manifestSkills = await discoverManifestSkills(sourcePath, manifest.pi?.skills);
  const manifestPrompts = await discoverManifestPrompts(sourcePath, manifest.pi?.prompts);
  const manifestThemes = await discoverManifestThemes(sourcePath, manifest.pi?.themes);

  const discovered = {
    extensions: new Map(),
    skills: manifestSkills ?? await discoverConventionSkills(sourcePath),
    prompts: manifestPrompts ?? await discoverConventionPrompts(sourcePath),
    themes: manifestThemes ?? await discoverConventionThemes(sourcePath),
  };

  for (const relativePath of manifestExtensions) {
    const absolutePath = path.join(sourcePath, relativePath.slice(2));
    if (!(await fileExists(absolutePath))) {
      throw new ExitError(`missing materialized source file referenced by manifest: ${relativePath}`, 2);
    }
    discovered.extensions.set(relativePath, relativePath);
  }

  return discovered;
}

function selectResources(discovered, expose = {}) {
  const selectedExtensions = normalizeSelectionIds(expose.extensions, {
    field: 'expose.extensions',
    kind: 'path',
  }) ?? Array.from(discovered.extensions.keys()).sort((left, right) => left.localeCompare(right));

  const selectedSkills = normalizeSelectionIds(expose.skills, {
    field: 'expose.skills',
    kind: 'name',
  }) ?? Array.from(discovered.skills.keys()).sort((left, right) => left.localeCompare(right));

  const selectedPrompts = normalizeSelectionIds(expose.prompts, {
    field: 'expose.prompts',
    kind: 'path',
  }) ?? Array.from(discovered.prompts.keys()).sort((left, right) => left.localeCompare(right));

  const selectedThemes = normalizeSelectionIds(expose.themes, {
    field: 'expose.themes',
    kind: 'name',
  }) ?? Array.from(discovered.themes.keys()).sort((left, right) => left.localeCompare(right));

  const selected = {
    extensions: [],
    skills: [],
    prompts: [],
    themes: [],
  };

  for (const extensionId of selectedExtensions) {
    const relativePath = discovered.extensions.get(extensionId);
    if (!relativePath) {
      throw new ExitError(`missing selected resource: extension ${extensionId}`, 3);
    }
    selected.extensions.push({ id: extensionId, relativePath });
  }

  for (const skillName of selectedSkills) {
    const relativePath = discovered.skills.get(skillName);
    if (!relativePath) {
      throw new ExitError(`missing selected resource: skill ${skillName}`, 3);
    }
    selected.skills.push({ id: skillName, relativePath });
  }

  for (const promptId of selectedPrompts) {
    const relativePath = discovered.prompts.get(promptId);
    if (!relativePath) {
      throw new ExitError(`missing selected resource: prompt ${promptId}`, 3);
    }
    selected.prompts.push({ id: promptId, relativePath });
  }

  for (const themeName of selectedThemes) {
    const relativePath = discovered.themes.get(themeName);
    if (!relativePath) {
      throw new ExitError(`missing selected resource: theme ${themeName}`, 3);
    }
    selected.themes.push({ id: themeName, relativePath });
  }

  return selected;
}

function assertNoOverlaps(compiledPackages) {
  const seen = new Map();

  for (const pkg of compiledPackages) {
    for (const category of ['extensions', 'skills', 'prompts', 'themes']) {
      for (const resource of pkg.selected[category]) {
        const overlapKey = `${pkg.materializedKey}:${category}:${resource.relativePath}`;
        const existing = seen.get(overlapKey);
        if (existing) {
          throw new ExitError(
            `overlapping selected resource: ${category} ${resource.relativePath} claimed by ${existing} and ${pkg.packageId}`,
            3,
          );
        }
        seen.set(overlapKey, pkg.packageId);
      }
    }
  }
}

function toFacadePaths(selectedResources, pkg) {
  return {
    extensions: selectedResources.extensions.map((entry) => `./_source/${entry.relativePath.slice(2)}`),
    skills: selectedResources.skills.map((entry) => {
      // Pi expects the parent directory of SKILL.md to match the skill name.
      // If the SKILL.md parent directory would be '_source' (root-level skill),
      // we redirect it through a facade-local skills/<name>/ directory instead.
      // Use the sourceManifestName as the skill directory name for root-level skills.
      const sourceFacadePath = `./_source/${entry.relativePath.slice(2)}`;
      const parentDir = path.posix.basename(path.posix.dirname(sourceFacadePath));
      if (parentDir === '_source') {
        const skillDirName = pkg.sourceManifestName || pkg.packageId;
        return `./skills/${skillDirName}/SKILL.md`;
      }
      return sourceFacadePath;
    }),
    prompts: selectedResources.prompts.map((entry) => `./_source/${entry.relativePath.slice(2)}`),
    themes: selectedResources.themes.map((entry) => `./_source/${entry.relativePath.slice(2)}`),
  };
}

function buildMetadata(pkg) {
  return {
    schemaVersion: 1,
    packageId: pkg.packageId,
    source: {
      type: pkg.source.type,
      spec: pkg.source.spec,
      materializedKey: pkg.materializedKey,
    },
    sourceManifestName: pkg.sourceManifestName,
    sourceRoot: pkg.sourceRoot,
    selectedResources: {
      extensions: pkg.selected.extensions.map((entry) => entry.id),
      skills: pkg.selected.skills.map((entry) => entry.id),
      prompts: pkg.selected.prompts.map((entry) => entry.id),
      themes: pkg.selected.themes.map((entry) => entry.id),
    },
  };
}

async function pruneStaleArtifacts(directoryPath, keepNames, { artifactLabel }) {
  let entries = [];

  try {
    entries = await fs.readdir(directoryPath, { withFileTypes: true });
  } catch (error) {
    if (error && error.code === 'ENOENT') {
      return [];
    }
    throw error;
  }

  const warnings = [];
  for (const entry of entries.sort((left, right) => left.name.localeCompare(right.name))) {
    if (keepNames.has(entry.name)) {
      continue;
    }

    const artifactPath = path.join(directoryPath, entry.name);
    await fs.rm(artifactPath, { recursive: true, force: true });
    warnings.push({
      code: 'PI_PACKAGE_WARN_STALE_ARTIFACT_PRUNED',
      message: `Pruned stale generated ${artifactLabel} artifact: ${artifactPath}`,
      path: artifactPath,
    });
  }

  return warnings;
}

async function writeFacadePackage(pkg, packagesDir) {
  const packageDir = path.join(packagesDir, pkg.packageId);
  const metaDir = path.join(packageDir, 'meta');
  await fs.rm(packageDir, { recursive: true, force: true });
  await ensureDirectory(metaDir);

  const sourceLinkPath = path.join(packageDir, '_source');
  const relativeSourceTarget = path.relative(packageDir, pkg.sourceRoot);
  await fs.symlink(relativeSourceTarget, sourceLinkPath, 'dir');

  // For skills whose SKILL.md is at the source root (parent would be _source),
  // create a facade-local skills/<name>/ directory with a symlink to the actual SKILL.md.
  // This ensures Pi sees the correct parent directory name matching the skill name.
  const facadePaths = toFacadePaths(pkg.selected, pkg);
  for (const entry of pkg.selected.skills) {
    const sourceFacadePath = `./_source/${entry.relativePath.slice(2)}`;
    const parentDir = path.posix.basename(path.posix.dirname(sourceFacadePath));
    if (parentDir === '_source') {
      const skillDirName = pkg.sourceManifestName || pkg.packageId;
      const skillDir = path.join(packageDir, 'skills', skillDirName);
      await ensureDirectory(skillDir);
      const skillMdTarget = path.relative(skillDir, path.join(packageDir, '_source', entry.relativePath.slice(2)));
      await fs.symlink(skillMdTarget, path.join(skillDir, 'SKILL.md'));
    }
  }

  const packageJson = {
    name: pkg.packageId,
    private: true,
    version: '0.0.0-generated',
    pi: facadePaths,
  };

  await fs.writeFile(path.join(packageDir, 'package.json'), `${JSON.stringify(packageJson, null, 2)}\n`);
  await fs.writeFile(path.join(metaDir, 'source.json'), `${JSON.stringify(buildMetadata(pkg), null, 2)}\n`);

  return packageDir;
}

async function compileDeclarations({ declarationsPath, outputDir }) {
  const declarationsDir = path.dirname(declarationsPath);
  const declarations = await readJson(declarationsPath, {
    exitCode: 2,
    label: 'declarations file',
  });

  if (!isPlainObject(declarations) || !Array.isArray(declarations.packages)) {
    throw new ExitError('malformed declaration contract: top-level packages array is required', 3);
  }

  await ensureDirectory(outputDir);
  const sourcesDir = path.join(outputDir, 'sources');
  const packagesDir = path.join(outputDir, 'packages');
  await ensureDirectory(sourcesDir);
  await ensureDirectory(packagesDir);

  const seenPackageIds = new Set();
  const sourceCache = new Map();
  const compiledPackages = [];

  const sortedDeclarations = [...declarations.packages].sort((left, right) => {
    const leftId = left?.packageId ?? '';
    const rightId = right?.packageId ?? '';
    return leftId.localeCompare(rightId);
  });

  for (const declaration of sortedDeclarations) {
    if (!isPlainObject(declaration)) {
      throw new ExitError('malformed declaration contract: package declarations must be objects', 3);
    }

    ensurePathSafePackageId(declaration.packageId);
    if (seenPackageIds.has(declaration.packageId)) {
      throw new ExitError(`malformed declaration contract: duplicate packageId ${declaration.packageId}`, 3);
    }
    seenPackageIds.add(declaration.packageId);

    if (!isPlainObject(declaration.source)) {
      throw new ExitError(`malformed declaration contract: source block required for ${declaration.packageId}`, 3);
    }

    const source = declaration.source;
    if (typeof source.type !== 'string' || source.type.length === 0) {
      throw new ExitError(`malformed declaration contract: source.type required for ${declaration.packageId}`, 3);
    }
    if (typeof source.spec !== 'string' || source.spec.length === 0) {
      throw new ExitError(`malformed declaration contract: source.spec required for ${declaration.packageId}`, 3);
    }
    if (declaration.expose != null && !isPlainObject(declaration.expose)) {
      throw new ExitError(`malformed declaration contract: expose must be an object for ${declaration.packageId}`, 3);
    }

    if (source.type === 'local') {
      continue;
    }

    if (typeof source.materializedPath !== 'string' || source.materializedPath.length === 0) {
      throw new ExitError(`malformed declaration contract: source.materializedPath required for ${declaration.packageId}`, 3);
    }

    const resolvedMaterializedPath = path.resolve(declarationsDir, source.materializedPath);
    let sourceStats;
    try {
      sourceStats = await fs.stat(resolvedMaterializedPath);
    } catch (error) {
      if (error && error.code === 'ENOENT') {
        throw new ExitError(`missing materialized source for ${declaration.packageId}: ${resolvedMaterializedPath}`, 2);
      }
      throw error;
    }

    if (!sourceStats.isDirectory()) {
      throw new ExitError(`missing materialized source for ${declaration.packageId}: ${resolvedMaterializedPath}`, 2);
    }

    const manifest = await loadSourceManifest(resolvedMaterializedPath);
    const materializedKey = buildMaterializedKey(source);
    const sourceRoot = path.join(sourcesDir, materializedKey);
    if (!sourceCache.has(materializedKey)) {
      await ensureSymlink(sourceRoot, resolvedMaterializedPath);
      sourceCache.set(materializedKey, {
        materializedKey,
        sourceRoot,
        manifest,
        discovered: await discoverResources(resolvedMaterializedPath, manifest),
      });
    }

    const cachedSource = sourceCache.get(materializedKey);
    const selected = selectResources(cachedSource.discovered, declaration.expose ?? {});

    compiledPackages.push({
      packageId: declaration.packageId,
      source,
      materializedKey,
      sourceRoot,
      sourceManifestName: cachedSource.manifest.name,
      selected,
    });
  }

  assertNoOverlaps(compiledPackages);

  const warnings = [
    ...await pruneStaleArtifacts(packagesDir, new Set(compiledPackages.map((pkg) => pkg.packageId)), {
      artifactLabel: 'package',
    }),
    ...await pruneStaleArtifacts(sourcesDir, new Set(Array.from(sourceCache.keys())), {
      artifactLabel: 'source',
    }),
  ];

  const reportPackages = [];
  for (const pkg of compiledPackages) {
    const facadeDir = await writeFacadePackage(pkg, packagesDir);
    reportPackages.push({
      packageId: pkg.packageId,
      facadeDir,
      materializedKey: pkg.materializedKey,
      sourceRoot: pkg.sourceRoot,
      sourceManifestName: pkg.sourceManifestName,
      selectedResources: {
        extensions: pkg.selected.extensions.map((entry) => entry.id),
        skills: pkg.selected.skills.map((entry) => entry.id),
        prompts: pkg.selected.prompts.map((entry) => entry.id),
        themes: pkg.selected.themes.map((entry) => entry.id),
      },
    });
  }

  return {
    schemaVersion: 1,
    packages: reportPackages,
    sources: Array.from(sourceCache.values())
      .map((entry) => ({
        materializedKey: entry.materializedKey,
        sourceRoot: entry.sourceRoot,
        sourceManifestName: entry.manifest.name,
      }))
      .sort((left, right) => left.materializedKey.localeCompare(right.materializedKey)),
    warnings,
  };
}

async function main() {
  const options = parseArgs(process.argv);
  const result = await compileDeclarations(options);
  process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
}

main().catch((error) => {
  if (error instanceof ExitError) {
    process.stderr.write(`${error.message}\n`);
    process.exit(error.exitCode);
  }

  process.stderr.write(`internal compiler failure: ${error instanceof Error ? error.stack ?? error.message : String(error)}\n`);
  process.exit(3);
});
