---
description: Detailed feature planning workflow including scoping, task breakdown, and risk assessment.
---

<!-- Command: /plan [feature] -->
<!-- Source: _workflow-source/plan.md -->
<!-- Run before starting any new feature -->

# /plan — Feature Planning

## Input

Feature: $ARGUMENTS

---

## Output Format

Prefix output with: `## 📋 PLAN`

Tone: exploratory — flag unknowns, surface assumptions. Do NOT proceed to code. Wait for user confirmation.

---

## Steps

### 1. SCOPE

Map out exactly what needs to change, layer by layer:

- **Components** (`src/components/`): files to create or modify — path + reason
- **Hooks** (`src/hooks/`): logic hooks to create or modify
- **Service Hooks** (`src/hooks/api/`): API wrappers needed — name + endpoint
- **Store** (`src/store/`): global UI state changes, if any
- **Translations** (`messages/`): new keys for `en.json` + `id.json`
- **Types** (`src/types/`): new shared interfaces, if any
- **Validations** (`src/lib/validations/`): new Zod schemas, if any

### 2. UNKNOWNS

List anything that must be investigated before coding can start. Examples:

- "Does the BE already expose this endpoint?"
- "Which existing component is closest to what we need?"

If none → state: "No unknowns."

### 3. TASKS

Format: `[ ] [TAG] [verb] [target] — est. Xmin`

- Each task: **5–30 min**. If larger, split it.
- Ordered by dependency.
- Tags: `[UI]` `[HOOK]` `[STORE]` `[API]` `[TEST]` `[i18n]`

### 4. RISKS

Format: `[HIGH/MED/LOW] [risk] → [mitigation]`

Only flag risks that would block or significantly change execution.

### 5. CONFIRMATION

Generate 1–3 questions specific to this feature that need user answers before proceeding.

If no open questions → state: "No blockers — ready to execute."

---

## Hard Rules

- Do not start coding until user responds to CONFIRMATION
- Output sections in order: SCOPE → UNKNOWNS → TASKS → RISKS → CONFIRMATION
- If plan exceeds 50 tasks, split into phases — output Phase 1 first, ask user before continuing
