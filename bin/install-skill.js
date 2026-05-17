#!/usr/bin/env node
const fs = require('fs');
const path = require('path');
const os = require('os');

const args = process.argv.slice(2);
const force = args.includes('--force');
const names = args.filter((a) => !a.startsWith('--'));

if (names.length === 0) {
  console.error('Usage: npx github:sheinkman/skills <skill-name> [<skill-name>...] [--force]');
  process.exit(1);
}

const repoRoot = path.resolve(__dirname, '..');
const destRoot = path.join(os.homedir(), '.claude', 'skills');
fs.mkdirSync(destRoot, { recursive: true });

function copyDir(src, dest) {
  fs.mkdirSync(dest, { recursive: true });
  for (const entry of fs.readdirSync(src, { withFileTypes: true })) {
    if (entry.name === '.DS_Store') continue;
    const s = path.join(src, entry.name);
    const d = path.join(dest, entry.name);
    if (entry.isDirectory()) copyDir(s, d);
    else fs.copyFileSync(s, d);
  }
}

let hadError = false;
for (const name of names) {
  const src = path.join(repoRoot, name);
  if (!fs.existsSync(src) || !fs.statSync(src).isDirectory()) {
    console.error(`Skill "${name}" not found in repo.`);
    hadError = true;
    continue;
  }
  const dest = path.join(destRoot, name);
  if (fs.existsSync(dest) && !force) {
    console.error(`Refusing to overwrite ${dest}. Re-run with --force to replace it.`);
    hadError = true;
    continue;
  }
  if (fs.existsSync(dest)) fs.rmSync(dest, { recursive: true, force: true });
  copyDir(src, dest);
  console.log(`Installed ${name} -> ${dest}`);
}

process.exit(hadError ? 1 : 0);
