'use strict';
/* One release version: godot/project.godot. App export presets, build scripts and the README must agree, since a stale
   preset can silently ship under the wrong marketing version (and a stale README badge / What's new section is the
   same drift, just visible instead of shipped). Run: npm run check:version */
const fs = require('fs');
const path = require('path');

const root = path.join(__dirname, '..');
const project = fs.readFileSync(path.join(root, 'godot/project.godot'), 'utf8');
const found = project.match(/^config\/version="([^"]+)"$/m);
if (!found) fail('godot/project.godot has no application/config/version');
const version = found[1];
if (!/^\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?$/.test(version)) fail(`project version is not semver-like: ${version}`);

const readme = fs.readFileSync(path.join(root, 'README.md'), 'utf8');
if (!readme.includes(`badge/version-${version}`)) fail(`README version badge does not match project version ${version}`);
if (!readme.includes(`## What's new in ${version}`)) fail(`README "What's new in ${version}" section is missing`);

const presets = fs.readFileSync(path.join(root, 'godot/export_presets.cfg'), 'utf8');
const versions = [...presets.matchAll(/^(?:application\/short_version|application\/file_version|application\/product_version|version\/name)="([^"]+)"$/gm)]
  .map(m => m[1]);
if (!versions.length) fail('export_presets.cfg has no version fields');
for (const v of versions) {
  const comparable = v.split('.').length === 4 && v.endsWith('.0') ? v.slice(0, -2) : v;
  if (comparable !== version) fail(`export preset version ${v} does not match project version ${version}`);
}

for (const script of ['tools/build-android.sh', 'tools/build-ios.sh']) {
  const text = fs.readFileSync(path.join(root, script), 'utf8');
  if (!text.includes('godot/project.godot')) fail(`${script} does not read the project version`);
  if (/VERSION="\$\{VERSION:-[0-9]/.test(text)) fail(`${script} still has a hard-coded fallback version`);
}

console.log(`release version ${version} is consistent`);

function fail(msg) {
  console.error('version check FAILED: ' + msg);
  process.exit(1);
}
