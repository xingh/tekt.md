#!/usr/bin/env node
// Checks that tekt.catalog.yaml stays the source of truth for the installers:
// every install_* / Install-* function is claimed by a catalog entry, and every
// entry says how to detect and how to install itself.
//
//   node scripts/check-catalog.js
//
// The installers themselves stay dependency-free; this runs in CI/dev only.
const fs = require("fs");
const path = require("path");
const yaml = require("js-yaml");

const root = path.join(__dirname, "..");
const read = (f) => fs.readFileSync(path.join(root, f), "utf8");

const catalog = yaml.load(read("tekt.catalog.yaml"));
const sh = read("install.sh");
const ps = read("install.ps1");

const entries = [];
for (const [layer, body] of Object.entries(catalog.layers || {})) {
  for (const tool of body.tools || []) entries.push({ layer, tool });
}

const problems = [];

// Functions the scripts define, minus the generic helpers that belong to no tool.
const generic = new Set(["install_catalog_tool", "Install-CatalogEntry", "Install-CatalogLayer", "Install-Winget"]);
const shFns = [...sh.matchAll(/^(install_[a-z0-9_]+)\(\)/gm)].map((m) => m[1]).filter((f) => !generic.has(f));
const psFns = [...ps.matchAll(/^function (Install-[A-Za-z0-9]+)/gm)].map((m) => m[1]).filter((f) => !generic.has(f));

const claimed = (field) => {
  const set = new Set();
  for (const { tool } of entries) {
    const v = tool[field];
    if (v) String(v).split(/[,\s]+/).filter(Boolean).forEach((f) => set.add(f));
  }
  return set;
};
const claimedSh = claimed("installer");
const claimedPs = claimed("installer_windows");

for (const fn of shFns) if (!claimedSh.has(fn)) problems.push(`install.sh ${fn}() has no catalog entry (add installer: ${fn})`);
for (const fn of psFns) if (!claimedPs.has(fn)) problems.push(`install.ps1 ${fn} has no catalog entry (add installer_windows: ${fn})`);

for (const f of claimedSh) if (!sh.includes(`${f}()`)) problems.push(`catalog installer: ${f} is not a function in install.sh`);
for (const f of claimedPs) {
  if (f === "Install-Winget") continue;
  if (!ps.includes(`function ${f}`)) problems.push(`catalog installer_windows: ${f} is not a function in install.ps1`);
}

// Every entry that a platform can install needs detection, and a way to install.
const platformFields = ["", "_macos", "_linux", "_windows"];
for (const { layer, tool } of entries) {
  const id = `${layer}/${tool.key || tool.name}`;
  if (!tool.key) problems.push(`${id} has no key:`);
  const installs = platformFields.some((s) => tool[`install${s}`]);
  const steps = platformFields.some((s) => tool[`install_steps${s}`]);
  const owned = tool.installer || tool.installer_windows;
  if (!installs && !steps && !owned) problems.push(`${id} has no install, install_steps, or installer`);
  if (installs && !tool.cmd && !tool.detect) problems.push(`${id} is installable but has no cmd:/detect:`);
  if (tool.managed && !["catalog", "script"].includes(tool.managed)) problems.push(`${id} managed: must be catalog or script`);
  if (tool.managed === "catalog" && !installs) problems.push(`${id} is managed: catalog but has no install command`);
}

const order = catalog.install_order || [];
const layers = Object.keys(catalog.layers || {});
if (order.join() !== layers.join()) problems.push(`install_order ${order.join(" -> ")} does not match the layers in the catalog`);

if (problems.length) {
  console.error("catalog check failed:");
  for (const p of problems) console.error("  - " + p);
  process.exit(1);
}
console.log(`catalog ok - ${entries.length} entries, ${shFns.length} install.sh and ${psFns.length} install.ps1 functions claimed`);
