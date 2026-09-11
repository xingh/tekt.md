#!/usr/bin/env node
// Keeps _data/site.json in sync with the PROFILE in 00-arkitype.md.
//
// 00-arkitype.md is the override layer: its `profile:` YAML block is the source
// of truth for everything site-specific (name, tagline, brand, layers, nav…).
// _data/site.json is a generated mirror of `profile.site`, because Eleventy reads
// it as the global `site` data. Edit the profile, never site.json by hand.
//
//   node scripts/sync-profile.js          write _data/site.json from the profile
//   node scripts/sync-profile.js --check  exit 1 if site.json and the profile differ
const fs = require("fs");
const path = require("path");
const yaml = require("js-yaml");

const root = path.join(__dirname, "..");
const arkitype = path.join(root, "00-arkitype.md");
const mirror = path.join(root, "_data", "site.json");

// The first ```yaml fence whose content starts with `profile:`.
function readProfile() {
  const text = fs.readFileSync(arkitype, "utf8");
  const fences = [...text.matchAll(/```ya?ml\n([\s\S]*?)```/g)].map((m) => m[1]);
  const block = fences.find((body) => /^profile:\s*$/m.test(body.split("\n")[0]));
  if (!block) throw new Error(`No \`profile:\` YAML block found in ${path.relative(root, arkitype)}`);
  const data = yaml.load(block);
  if (!data || !data.profile || !data.profile.site) {
    throw new Error("The profile block has no `profile.site` section");
  }
  return data.profile.site;
}

function main() {
  const check = process.argv.includes("--check");
  const site = readProfile();
  const next = JSON.stringify(site, null, 2) + "\n";

  if (check) {
    const current = fs.existsSync(mirror) ? JSON.parse(fs.readFileSync(mirror, "utf8")) : null;
    if (JSON.stringify(current) !== JSON.stringify(site)) {
      console.error("_data/site.json is out of sync with profile.site in 00-arkitype.md.");
      console.error("Edit the profile, then run: npm run profile");
      process.exit(1);
    }
    console.log("profile: _data/site.json matches profile.site in 00-arkitype.md");
    return;
  }

  const prev = fs.existsSync(mirror) ? fs.readFileSync(mirror, "utf8") : "";
  if (prev !== next) {
    fs.writeFileSync(mirror, next);
    console.log("profile: wrote _data/site.json from profile.site in 00-arkitype.md");
  } else {
    console.log("profile: _data/site.json already up to date");
  }
}

try {
  main();
} catch (err) {
  console.error(`profile: ${err.message}`);
  process.exit(1);
}
