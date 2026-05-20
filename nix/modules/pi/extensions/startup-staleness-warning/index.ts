const fs = require('node:fs/promises');
const path = require('node:path');
const os = require('node:os');

const STATUS_ENV_VAR = 'PI_MANAGED_PACKAGE_STARTUP_STATUS_PATH';
const SNAPSHOT_TTL_MS = 60_000;
const STATUS_ID = 'managed-package-startup-warning';

function getNow(ctx) {
  const candidate = ctx?.now ?? process.env.PI_STARTUP_WARNING_NOW;
  const parsed = new Date(candidate ?? Date.now());
  return Number.isNaN(parsed.getTime()) ? new Date() : parsed;
}

function sortPackageIds(packageIds) {
  return Array.isArray(packageIds)
    ? [...packageIds].filter((value) => typeof value === 'string' && value.length > 0).sort((left, right) => left.localeCompare(right))
    : [];
}

function normalizeSourceList(payload, status) {
  return Array.isArray(payload?.sources)
    ? payload.sources
      .filter((entry) => entry && entry.status === status)
      .map((entry) => ({
        ...entry,
        packageIds: sortPackageIds(entry.packageIds),
      }))
      .sort((left, right) => {
        const leftPackages = left.packageIds.join(',');
        const rightPackages = right.packageIds.join(',');
        return leftPackages.localeCompare(rightPackages) || String(left.sourceKey ?? '').localeCompare(String(right.sourceKey ?? ''));
      })
    : [];
}

function validatePayload(payload) {
  if (!payload || typeof payload !== 'object') {
    return false;
  }

  if (payload.schemaVersion !== 1 || payload.mode !== 'startup') {
    return false;
  }

  if (!payload.summary || typeof payload.summary !== 'object') {
    return false;
  }

  return Array.isArray(payload.sources);
}

async function resolveOwnedSnapshotPath(snapshotPath) {
  if (typeof snapshotPath !== 'string' || snapshotPath.length === 0) {
    return null;
  }

  const startupStatusDir = path.join(os.homedir(), '.pi', 'agent', 'startup-status');

  try {
    const [realSnapshotPath, realStartupStatusDir] = await Promise.all([
      fs.realpath(snapshotPath),
      fs.realpath(startupStatusDir),
    ]);
    const relative = path.relative(realStartupStatusDir, realSnapshotPath);
    if (relative === '' || relative.startsWith('..') || path.isAbsolute(relative)) {
      return null;
    }
    return realSnapshotPath;
  } catch {
    return null;
  }
}

function isFreshSnapshot(payload, now) {
  const createdAt = new Date(payload.createdAt ?? '');
  const expiresAt = new Date(payload.expiresAt ?? '');

  if (Number.isNaN(createdAt.getTime()) || Number.isNaN(expiresAt.getTime())) {
    return false;
  }

  if (expiresAt.getTime() - createdAt.getTime() > SNAPSHOT_TTL_MS) {
    return false;
  }

  return now.getTime() - createdAt.getTime() <= SNAPSHOT_TTL_MS && now.getTime() <= expiresAt.getTime();
}

function buildSection(title, entries, formatter) {
  if (entries.length === 0) {
    return [];
  }

  return [
    `${title} (${entries.length}):`,
    ...entries.map((entry) => formatter(entry)),
  ];
}

function formatStaleLine(entry) {
  if (entry.source?.type === 'npm') {
    return `- ${entry.packageIds.join(', ')} :: ${entry.source.packageName} ${entry.installedVersion} -> ${entry.latestVersion}`;
  }

  if (entry.source?.type === 'git') {
    return `- ${entry.packageIds.join(', ')} :: ${entry.source.spec} (${entry.installedCommit} -> ${entry.remote?.commit ?? 'unknown'})`;
  }

  return `- ${entry.packageIds.join(', ')}`;
}

function formatUnknownLine(entry) {
  return `- ${entry.packageIds.join(', ')} :: [${entry.reasonCode ?? 'UNKNOWN'}] ${entry.reason ?? 'remote status unavailable'}`;
}

function buildNotificationMessage(staleEntries, unknownEntries) {
  const lines = [
    'Managed Pi packages/plugins need attention.',
    '',
    ...buildSection('Stale managed package sources', staleEntries, formatStaleLine),
  ];

  if (staleEntries.length > 0 && unknownEntries.length > 0) {
    lines.push('');
  }

  lines.push(...buildSection('Unknown managed package sources', unknownEntries, formatUnknownLine));
  lines.push('', 'Inspect with check-updates --dry-run.', 'Apply changes with home-manager switch --flake .#<hostname>.');

  return lines.join('\n');
}

function buildStatusSummary(staleEntries, unknownEntries) {
  const parts = [];

  if (staleEntries.length > 0) {
    parts.push(`${staleEntries.length} stale`);
  }
  if (unknownEntries.length > 0) {
    parts.push(`${unknownEntries.length} unknown`);
  }

  return `Managed packages/plugins: ${parts.join(', ')} — run check-updates --dry-run`;
}

async function consumeSnapshot(snapshotPath) {
  try {
    await fs.rm(snapshotPath, { force: true });
  } catch {
    // Best-effort consume-once cleanup.
  }
}

function clearStatus(ctx) {
  if (ctx?.ui && typeof ctx.ui.setStatus === 'function') {
    ctx.ui.setStatus(STATUS_ID, null);
  }
}

async function sessionStart(ctx) {
  const snapshotPath = process.env[STATUS_ENV_VAR] ?? ctx?.env?.[STATUS_ENV_VAR];
  const ownedSnapshotPath = await resolveOwnedSnapshotPath(snapshotPath);

  if (!ownedSnapshotPath) {
    clearStatus(ctx);
    return;
  }

  let payload;
  try {
    payload = JSON.parse(await fs.readFile(ownedSnapshotPath, 'utf8'));
  } catch {
    clearStatus(ctx);
    return;
  }

  if (!validatePayload(payload) || !isFreshSnapshot(payload, getNow(ctx))) {
    clearStatus(ctx);
    return;
  }

  const staleEntries = normalizeSourceList(payload, 'stale');
  const unknownEntries = normalizeSourceList(payload, 'unknown');

  if (staleEntries.length === 0 && unknownEntries.length === 0) {
    await consumeSnapshot(ownedSnapshotPath);
    return;
  }

  const message = buildNotificationMessage(staleEntries, unknownEntries);
  const statusText = buildStatusSummary(staleEntries, unknownEntries);

  if (ctx?.ui && typeof ctx.ui.notify === 'function') {
    ctx.ui.notify({
      level: 'warning',
      title: 'Managed Pi packages/plugins need attention',
      message,
      id: STATUS_ID,
    });
  }

  if (ctx?.ui && typeof ctx.ui.setStatus === 'function') {
    ctx.ui.setStatus(STATUS_ID, statusText);
  }

  await consumeSnapshot(ownedSnapshotPath);
}

// Pi extension factory: receives ExtensionAPI, registers session_start handler
function startupStalenessWarning(pi) {
  pi.on('session_start', async (_event, ctx) => sessionStart(ctx));
}

// Default export for Pi's extension loader
module.exports = startupStalenessWarning;
module.exports.default = startupStalenessWarning;

// Also expose hooks for the test harness
module.exports.hooks = { session_start: sessionStart };
