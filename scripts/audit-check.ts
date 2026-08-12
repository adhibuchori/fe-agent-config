#!/usr/bin/env bun
/**
 * Security audit gate — wraps `bun audit --json`.
 *
 * As of Bun 1.3.14 that command has two defects which make it unusable directly:
 *   1. `--audit-level` is accepted but ignored — any advisory at all exits 1
 *   2. the registry's gzip response is never decompressed, so the report is unreadable
 *
 * This decodes the response, keeps only advisories that match a version actually
 * installed, and fails on high/critical alone. When Bun starts decompressing its
 * own output the plain-JSON branch takes over, so this keeps working unchanged.
 *
 * Exit code 1 if a blocking advisory matches an installed version, or if the
 * report cannot be read — an unreadable security report is never a pass.
 */

import { readdirSync, readFileSync } from 'fs';
import { join } from 'path';

const BLOCKING = new Set(['high', 'critical']);

interface Advisory {
  url: string;
  title: string;
  severity: string;
  vulnerable_versions: string;
}

type Report = Record<string, Advisory[]>;

/* ── Run bun audit and decode whatever it hands back ────────────────────────── */

function readReport(): Report {
  const proc = Bun.spawnSync(['bun', 'audit', '--json'], { stdout: 'pipe', stderr: 'pipe' });
  const raw = new Uint8Array(proc.stdout);

  /* No advisories at all — bun writes nothing. */
  if (raw.length === 0) return {};

  const isGzipped = raw[0] === 0x1f && raw[1] === 0x8b;
  let text: string;
  try {
    text = new TextDecoder().decode(isGzipped ? Bun.gunzipSync(raw) : raw);
  } catch (error: unknown) {
    throw new Error(`could not decode audit output: ${getMessage(error)}`, { cause: error });
  }

  /* Bun prefixes a version banner when stdout is a TTY; drop anything before the JSON. */
  const start = text.indexOf('{');
  if (start === -1) throw new Error('audit output contained no JSON object');

  try {
    return JSON.parse(text.slice(start)) as Report;
  } catch (error: unknown) {
    throw new Error(`could not parse audit JSON: ${getMessage(error)}`, { cause: error });
  }
}

function getMessage(error: unknown): string {
  return error instanceof Error ? error.message : 'unexpected error';
}

/* ── Map every installed copy of every package to its version(s) ────────────── */

function collectInstalled(nodeModules: string, found: Map<string, Set<string>>): void {
  let entries;
  try {
    entries = readdirSync(nodeModules, { withFileTypes: true });
  } catch {
    return;
  }

  for (const entry of entries) {
    if (!entry.isDirectory() || entry.name === '.bin') continue;

    /* Scope directories hold packages one level deeper. */
    if (entry.name.startsWith('@')) {
      collectInstalled(join(nodeModules, entry.name), found);
      continue;
    }

    const pkgDir = join(nodeModules, entry.name);
    try {
      const pkg = JSON.parse(readFileSync(join(pkgDir, 'package.json'), 'utf-8'));
      if (pkg.name && pkg.version) {
        const versions = found.get(pkg.name) ?? new Set<string>();
        versions.add(pkg.version);
        found.set(pkg.name, versions);
      }
    } catch {
      /* Not a package directory — skip it. */
    }

    collectInstalled(join(pkgDir, 'node_modules'), found);
  }
}

/* ── Match advisories against what is actually installed ────────────────────── */

interface Finding {
  name: string;
  versions: string[];
  advisory: Advisory;
}

function findBlocking(report: Report, installed: Map<string, Set<string>>): Finding[] {
  const findings: Finding[] = [];

  for (const [name, advisories] of Object.entries(report)) {
    const present = [...(installed.get(name) ?? [])];
    for (const advisory of advisories) {
      if (!BLOCKING.has(advisory.severity)) continue;
      const hit = present.filter((v) => Bun.semver.satisfies(v, advisory.vulnerable_versions));
      if (hit.length > 0) findings.push({ name, versions: hit, advisory });
    }
  }

  return findings;
}

/* ── Output ─────────────────────────────────────────────────────────────────── */

function out(line: string): void {
  process.stdout.write(`${line}\n`);
}

function fail(line: string): void {
  process.stderr.write(`${line}\n`);
}

/* ── Report ─────────────────────────────────────────────────────────────────── */

let report: Report;
try {
  report = readReport();
} catch (error: unknown) {
  fail(`[audit] ✗ ${getMessage(error)}`);
  process.exit(1);
}

const installed = new Map<string, Set<string>>();
collectInstalled(join(process.cwd(), 'node_modules'), installed);

const findings = findBlocking(report, installed);
const advisoryCount = Object.values(report).reduce((n, list) => n + list.length, 0);

out(`[audit] ${advisoryCount} advisories reported, ${installed.size} packages installed`);

if (findings.length === 0) {
  out('[audit] ✓ No high or critical advisories affect installed versions.');
  process.exit(0);
}

fail(`\n[audit] ✗ ${findings.length} blocking advisories:\n`);
for (const { name, versions, advisory } of findings) {
  fail(`  ${name}@${versions.join(', ')} — ${advisory.severity}`);
  fail(`    ${advisory.title}`);
  fail(`    affects ${advisory.vulnerable_versions} · ${advisory.url}\n`);
}
fail('[audit] Fix with a dependency bump, or pin a patched version via "overrides".');
process.exit(1);
