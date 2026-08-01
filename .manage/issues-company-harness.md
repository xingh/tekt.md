# Company Harness — Product Backlog (Issue #21)

This backlog plans the work to let a user install Tekt, enter a CLI, choose a company type, and generate a synchronized `company_harness` (tools, schema, process, roles, and operations).

## Epic A — Company Harness CLI & Onboarding

- [ ] **A1: Add `tekt` CLI command router with `create` namespace**
  - Problem: `create` is not currently a recognized command.
  - Deliverable: `tekt create company_harness --type <company_type>` entrypoint.
  - Acceptance: user can run command from terminal after install without manual script editing.

- [ ] **A2: Build interactive company type selector**
  - Deliverable: guided prompts + non-interactive flags.
  - Initial company types: agency, SaaS startup, operations-heavy SMB, internal IT team.
  - Acceptance: command outputs a valid harness config for each type.

- [ ] **A3: Generate canonical harness manifest**
  - Deliverable: machine-readable manifest (YAML) defining selected tools, roles, processes, and deployment targets.
  - Acceptance: manifest validates against schema and supports round-trip edits.

## Epic B — Schema, Process, View, Editor System

- [ ] **B1: Define `company_harness` schema (v1)**
  - Includes: tools, integrations, roles, skills, workflows, policies, sync contracts.
  - Acceptance: schema includes versioning and migration strategy.

- [ ] **B2: Implement process templates per company type**
  - Deliverable: default process packs (lead capture, delivery, support, reporting).
  - Acceptance: each template references concrete apps + handoff states.

- [ ] **B3: Add read/write views for harness state**
  - Deliverable: CLI view commands (`tekt harness show`, `tekt harness diff`, `tekt harness validate`).
  - Acceptance: users can inspect full hierarchy and detect invalid references.

- [ ] **B4: Add editor workflow**
  - Deliverable: safe edit flow with schema validation and dry-run.
  - Acceptance: edits fail fast on invalid graph relationships.

## Epic C — App Collection Deployment

- [ ] **C1: Add app bundle catalog for business systems**
  - Initial bundles:
    - Control plane: Coolify (preferred), Docker fallback
    - CRM: NocoDB, Baserow
    - Drive: Filestash
    - Calendar: Cal.com
  - Acceptance: bundle definitions include ports, env vars, health checks, persistence.

- [ ] **C2: Implement deployment planner**
  - Deliverable: plan output before apply (resources, dependencies, conflicts).
  - Acceptance: users can run `plan` then `apply` with deterministic results.

- [ ] **C3: Implement one-command collection deployment**
  - Deliverable: deploy selected bundle from harness manifest.
  - Acceptance: deploy completes or rolls back cleanly on failure.

## Epic D — Universal Field Protocol, Sync, and Security

- [ ] **D1: Define universal field protocol (UFP)**
  - Deliverable: shared field mapping for cross-system entities (company, contact, task, document, calendar_event).
  - Acceptance: each app adapter maps to/from UFP with explicit transforms.

- [ ] **D2: Build sync engine + conflict policy**
  - Deliverable: event-driven sync with idempotency keys and reconciliation jobs.
  - Acceptance: retries are safe; drift report is generated.

- [ ] **D3: Add secrets and auth model**
  - Deliverable: centralized credential references, rotation hooks, least-privilege role model.
  - Acceptance: no plaintext secrets in manifests; startup checks block unsafe config.

- [ ] **D4: Add operations reliability pack**
  - Deliverable: health monitors, backups, restore drills, and upgrade playbooks.
  - Acceptance: periodic backup/restore validation + SLA/SLO checklist.

## Epic E — UX, Documentation, and Adoption

- [ ] **E1: First-run onboarding experience**
  - Deliverable: explain generated stack and why each tool was selected.
  - Acceptance: user can accept defaults or swap alternatives before deploy.

- [ ] **E2: Author docs for company harness lifecycle**
  - Deliverable: create → plan → deploy → sync → operate → evolve.
  - Acceptance: docs include troubleshooting for command-not-found and environment setup.

- [ ] **E3: Add example harnesses**
  - Deliverable: sample manifests for each company type.
  - Acceptance: examples validate and deploy in dry-run mode.
