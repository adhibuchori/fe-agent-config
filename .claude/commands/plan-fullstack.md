---
description: Comprehensive fullstack planning workflow that validates Backend (BE) and Frontend (FE) before proposing changes.
---

<!-- Command: /plan-fullstack [feature] -->
<!-- Source: _workflow-source/plan-fullstack.md -->
<!-- Run before starting any new fullstack feature -->

# /plan-fullstack — Fullstack Feature Planning

## Input

Feature: $ARGUMENTS

> **Note:** FE never calls a service that sits behind <backend-service> (Hono) — a content service,
> a database, a third-party API holding server credentials. All data flows through the backend; FE
> only knows about its API endpoints.

---

## 1. RESEARCH (MANDATORY)

Before drafting the plan, you MUST perform the following research steps:

### 1.1 Backend (BE) Analysis

- **API**: Check `<backend-repo>/` for existing endpoints and controllers.
- **Logic**: Review service files in `<backend-repo>/src/` for business rules.
- **OpenAPI**: Check `openapi.json` (FE root) for the current API contract.

### 1.2 Frontend (FE) Analysis

- **Generated SDK**: Verify if `<frontend-repo>/src/lib/api/generated/` already includes the needed endpoints.
- **Components**: Identify existing UI components in `<frontend-repo>/src/components/` that can be reused.
- **Hooks**: Check `<frontend-repo>/src/hooks/` for existing logic hooks.
- **Translations**: Check `<frontend-repo>/src/messages/en.json` and `id.json` for missing keys.

### 1.3 Upstream Content Service (`<content-repo>/`) Analysis — only if the backend has one

- **Content types**: Check the existing content-type definitions in `<content-repo>/` for relevant models.
- **Fields**: Identify if new fields need to be added to existing content types.
- **Access control**: Review access rules if the feature involves restricted content.
- **Site-wide content**: Check shared, site-wide entries that may be affected.

---

## 2. SCOPE

Define what needs to be changed across every affected repository:

### Backend (BE) — `<backend-repo>/`

- [ ] **Endpoints**: List new or updated API endpoints.
- [ ] **Logic**: List services or controllers to implement.
- [ ] **Migration strategy**: Note any data migration requirements.
- [ ] **OpenAPI**: Confirm `openapi.json` will be updated to reflect new endpoints.

### Content Service (optional) — `<content-repo>/`

- [ ] **Content types**: List new content types or fields to add.
- [ ] **Access control**: Note any access rule changes needed.
- [ ] **Site-wide content**: List any shared entries to add or modify.
- [ ] **Content re-entry**: Flag if existing content needs to be updated after a schema change.

### Frontend (FE) — `<frontend-repo>/`

- [ ] **SDK Sync**: Check if `bun generate:api` is required after BE changes.
- [ ] **Service Hooks**: List new hooks in `src/hooks/api/` (naming: `use{Domain}{Action}`).
- [ ] **Logic Hooks**: List new hooks in `src/hooks/` for extracted business logic.
- [ ] **UI**: List components to create (kebab-case file, PascalCase export) or modify.
- [ ] **Translations**: List new keys for both `en.json` and `id.json`.
- [ ] **Store**: Check if any global UI state change is needed in `src/store/`.

---

## 3. TASKS

Format: `[ ] [TAG] [verb] [target] — est. Xmin`

- Each task: **5–30 min**. If larger, split it.
- Tags: `[CONTENT]` `[BE]` `[FE-API]` `[FE-UI]` `[FE-HOOK]` `[FE-i18n]` `[FE-STORE]`

Order by dependency — always content service → BE → FE:

1. _(if a content change is needed)_ **[CONTENT]** Add/modify content types or fields in `<content-repo>/`.
2. **[BE]** Implement controllers and services in `<backend-repo>/`.
3. **[BE]** Update `openapi.json` to reflect new endpoints.
4. **[FE-API]** Run `bun generate:api` and create service hooks in `src/hooks/api/`.
5. **[FE-UI]** / **[FE-HOOK]** Build/Modify components and logic hooks in `<frontend-repo>/`.
6. _(if strings changed)_ **[FE-i18n]** Add translations to both `en.json` and `id.json`.

---

## 4. RISKS

Format: `[HIGH/MED/LOW] [risk] → [mitigation]`

- Flag potential breaking changes in the API contract (`openapi.json`).
- Flag hydration issues or locale mismatches.
- Flag if a content-schema change requires content re-entry.

---

## 5. CONFIRMATION

Generate 1–3 questions **specific to this feature** that need user answers before execution starts. Examples of the kind of questions to ask (do not copy verbatim — derive from the actual feature):

- Is the proposed API contract (endpoint shape, request/response) aligned with what the BE team expects?
- Are there content implications that require coordination with content editors?
- Are there any UI constraints, brand guidelines, or copy decisions that must be confirmed first?

If no open questions → state: "No blockers — ready to execute."

---

## Hard Rules (Fullstack)

- **Do not skip BE research**: Always verify if the backend supports the feature before planning the FE.
- **SDK Rule**: Always use the generated SDK from `src/lib/api/generated/`. If it's missing an endpoint, the task is to update the BE and regenerate first.
- **Upstream services are invisible to FE**: Never plan a direct fetch to anything behind <backend-service>.
- **Sync i18n**: Never add a translation to one file without the other.

## Checks every fullstack plan carries

- **Authorization is the backend's.** Each new endpoint is scoped to the roles that may call it and
  enforced on the server; a frontend guard is a convenience, never the check (AGENTS.md §M).
- **States.** Every new screen names its loading, empty and error states and where each lives (§N).
- **Keys.** A new service hook comes with its entry in the query-key factory.
- **The store holds UI state only**: never server data, never the session.
- **An endpoint not built yet** is a labelled fixture under `src/testing/fixtures/` with a
  follow-up task, never data invented in a component.
- Where `payload.config.json` exists: the new routes' policies (and any exemption's reason) are
  planned on both sides, and `generate:endpoints` runs in both repos after the spec changes (§P).
