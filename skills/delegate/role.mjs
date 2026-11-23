#!/usr/bin/env node

import { existsSync, readFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { dirname, join, resolve } from 'node:path';

function projectRoot(cwd) {
  let current = cwd;
  while (true) {
    if (existsSync(join(current, '.pi', 'settings.json')) || existsSync(join(current, '.git'))) return current;
    const parent = dirname(current);
    if (parent === current) return cwd;
    current = parent;
  }
}

function overrideFor(file, role) {
  try {
    const entry = JSON.parse(readFileSync(file, 'utf8'))?.subagents?.agentOverrides;
    return entry && Object.hasOwn(entry, role) ? entry[role] : {};
  } catch (error) {
    if (error.code === 'ENOENT') return {};
    throw new Error(`${file}: ${error.message}`);
  }
}

function frontmatter(file) {
  const lines = readFileSync(file, 'utf8').split(/\r?\n/);
  const end = lines.indexOf('---', 1);
  if (lines[0] !== '---' || end < 0) throw new Error(`${file}: missing agent frontmatter`);
  const fields = {};
  let key;
  for (const line of lines.slice(1, end)) {
    const field = /^([\w-]+):[\t ]*(.*)$/.exec(line);
    if (field) {
      key = field[1];
      fields[key] = field[2].trim().replace(/^(['"])(.*)\1$/, '$2');
    } else if (key && /^[\t ]+-\s+/.test(line)) {
      fields[key] += `\n${line.trim().slice(1)}`;
    }
  }
  return fields;
}

function list(value) {
  if (value == null || value === false) return [];
  const parts = Array.isArray(value) ? value : value.split(/[,\n]/);
  return parts.map((part) => part.trim()).filter(Boolean);
}

function resolveRole(role) {
  if (!/^[a-z0-9][a-z0-9-]*$/.test(role ?? '')) throw new Error('Usage: role.mjs <role>');
  const root = projectRoot(process.cwd());
  const agentDir = resolve(process.env.PI_CODING_AGENT_DIR || join(homedir(), '.pi', 'agent'));
  const file = join(agentDir, 'agents', `${role}.md`);
  const fields = frontmatter(file);
  const user = overrideFor(join(agentDir, 'settings.json'), role);
  const project = overrideFor(join(root, '.pi', 'settings.json'), role);
  const effective = { ...fields, skills: fields.skill ?? fields.skills, ...user, ...project };
  if (Object.hasOwn(effective, 'fallbackModels')) throw new Error(`${role}: fallbackModels is unsupported`);
  if (effective.disabled === true || effective.disabled === 'true') throw new Error(`${role}: role is disabled`);
  const { model, thinking } = effective;
  if (!model || !thinking) throw new Error(`${role}: configure a model and thinking level`);
  const skills = list(effective.skills);
  const paths = skills.map((name) => {
    const local = join(root, '.pi', 'skills', name, 'SKILL.md');
    return existsSync(local) ? local : join(agentDir, 'skills', name, 'SKILL.md');
  });
  const explicit = list(effective.skillPath).map((entry) =>
    entry.startsWith('~/') ? join(homedir(), entry.slice(2)) : resolve(dirname(file), entry));
  return { role, model, thinking, skills, skillPaths: [...new Set([...paths, ...explicit])], mayDelegate: skills.includes('delegate') };
}

try {
  if (process.argv.length !== 3) throw new Error('Usage: role.mjs <role>');
  console.log(JSON.stringify(resolveRole(process.argv[2])));
} catch (error) {
  console.error(`role.mjs: ${error.message}`);
  process.exitCode = 1;
}
