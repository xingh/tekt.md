// Loads tekt.catalog.yaml, the same file install.sh / install.ps1 read, and
// flattens it into catalog entries grouped by kind (the four shelves:
// tool, agent, mcp, skill) for the home page and /catalog/.
const fs = require("fs");
const path = require("path");
const yaml = require("js-yaml");

// tekt layer → arkitype layer code (see the label table in the iterations plan)
const LAYER_CODE = {
  "tekt.dev": "01",
  "tekt.edge": "01",
  "tekt.base": "02",
  "tekt.iris": "03",
  "tekt.cloud": "04",
};

const text = (v) => (v == null ? "" : String(v).replace(/\s+/g, " ").trim());

module.exports = () => {
  const file = path.join(__dirname, "..", "tekt.catalog.yaml");
  const cat = yaml.load(fs.readFileSync(file, "utf8"));
  const entries = [];

  for (const [layer, def] of Object.entries(cat.layers || {})) {
    for (const t of def.tools || []) {
      entries.push({
        name: t.name,
        kind: t.kind || def.default_kind || "tool",
        layer,
        code: LAYER_CODE[layer] || "00",
        upstream: text(t.upstream),
        license: text(t.license),
        link: t.repo || t.docs || "",
        note: text(t.note),
        status: t.status || (t.optional ? "optional" : "installed"),
      });
    }
  }

  for (const [name, s] of Object.entries(cat.mcp_servers || {})) {
    entries.push({
      name,
      kind: "mcp",
      layer: "tekt.iris",
      code: "03",
      upstream: text(s.upstream),
      link: s.repo || "",
      note: text(s.summary),
      status: s.status || "default",
    });
  }

  for (const [name, s] of Object.entries(cat.skills || {})) {
    entries.push({
      name,
      kind: "skill",
      layer: "tekt.iris",
      code: "03",
      upstream: text(s.upstream),
      link: s.repo || "",
      note: text(s.summary),
      status: s.status || "curating",
    });
  }

  // Bring your own intelligence: providers Tekt points agents at, never ships.
  for (const [id, s] of Object.entries(cat.intelligence || {})) {
    const via = [s.connects && s.connects.includes("api") ? "API key" : "", ...(s.clients || [])].filter(Boolean);
    entries.push({
      name: s.name || id,
      kind: "intelligence",
      layer: "tekt.iris",
      code: "03",
      upstream: text(s.upstream),
      link: s.repo || "",
      note: text(s.summary) + (via.length ? ` Connect via: ${via.join(", ")}.` : ""),
      status: s.status || "bring-your-own",
    });
  }

  const byKind = { tool: [], agent: [], mcp: [], skill: [], intelligence: [] };
  for (const e of entries) (byKind[e.kind] = byKind[e.kind] || []).push(e);

  return { version: cat.catalog_version, positioning: cat.positioning, entries, byKind };
};
