---
description: Separation of Concerns audit — extract business logic from components into hooks and migrate shared UI state to Zustand stores.
---

<!-- Command: /review-soc [path] -->
<!-- Source: _workflow-source/review-soc.md -->
<!-- Run during refactoring or before PR -->

# /review-soc — Separation of Concerns Audit

Two-part audit: **Part A** extracts logic from UI components into hooks. **Part B** migrates shared UI state to Zustand stores. Both enforce the zero-tolerance SoC policy in AGENTS.md (Rules 5–8).

---

## Part A: Logic Extraction

### A1. Scan — What Must Leave the Component

Flag the component if **any** of the following are present (AGENTS.md Rule 6):

| Indicator                                  | Description                                                  | Severity    | Action                        |
| :----------------------------------------- | :----------------------------------------------------------- | :---------- | :---------------------------- |
| **useEffect with logic**                   | Any `useEffect` doing more than a trivial ref assignment     | 🔴 Critical | Extract to hook               |
| **useState for behavior/data**             | `useState` tracking async state, calculations, or data sync  | 🔴 Critical | Extract to hook               |
| **window.\_ / document.\_ / navigator.\*** | Any browser API call                                         | 🔴 Critical | Extract to hook               |
| **setTimeout / setInterval / rAF**         | Any timer or animation frame                                 | 🔴 Critical | Extract to hook               |
| **Observers**                              | `IntersectionObserver`, `ResizeObserver`, `MutationObserver` | 🔴 Critical | Extract to hook               |
| **async / await**                          | Any async function inside the component                      | 🔴 Critical | Extract to hook               |
| **useRef for DOM manipulation**            | `useRef` used for DOM operations or timing                   | 🔴 High     | Extract to hook               |
| **useCallback / useMemo with logic**       | Wrapping business logic, not just trivial forwarding         | 🔴 High     | Extract to hook               |
| **Form management**                        | `useForm`, Zod validation, submission handlers               | 🔴 High     | Extract to `use{Feature}Form` |
| **Derived data / complex computation**     | Multi-step transforms inside the component body              | 🟡 Medium   | Move to hook                  |
| **Navigation**                             | `router.push`, `router.back`                                 | 🔴 High     | Extract handler to hook       |

### A2. Safe UI State (The ONLY exceptions — may stay in component)

- `const [isOpen, setIsOpen] = useState(false)` — pure visibility toggle
- `const [activeTab, setActiveTab] = useState("default")` — pure navigation state
- `useRef<HTMLElement>(null)` — for passing to a DOM element as `ref` prop only
- Inline event handler that only calls `e.stopPropagation()` + one prop callback

**Everything else MUST be extracted.**

### A3. Stop Condition

**STOP and report clean** if:

- Component is purely `props → JSX`
- No hooks beyond the safe exceptions above

### A4. Extraction Rules

- **Hook placement**: `src/hooks/` — camelCase filename matching the export name (e.g., `useNavBehavior.ts` exports `useNavBehavior`)
- **One hook = one concern**: name it after the concern (`useScrollSpy`, `useContactForm`)
- **Hook must not return JSX or contain Tailwind classes** (Rule 7)
- **Hook may import from**: `src/lib/`, `src/store/`, `src/types/`
- **Return shape**: `{ renderData, eventHandlers, essentialState }`

### A5. Checklist Before Marking Extraction Complete

- [ ] Zero business logic in component: no API refs, no complex state, no effect syncing
- [ ] Component reads like a template — purely declarative JSX
- [ ] All hook interfaces fully typed (no `any`)
- [ ] Hook filename matches export name, placed in `src/hooks/`
- [ ] Quality gates pass: `bun fl && bun type-check`

---

## Part B: Zustand Store Migration

### B1. When to Migrate to Zustand

Migrate state from a local hook to a Zustand store when the state is:

- Shared across **multiple unrelated components** (e.g., theme, mobile menu open state)
- Better managed globally to keep UI components purely presentational
- Part of a complex UI flow involving multiple components

**Do NOT migrate if:**

- State is local to one component or one hook subtree → keep in `useState`
- State is server/API data → use TanStack Query (Rule 8)

### B2. Store Design Rules (AGENTS.md Rule 8)

- **Location**: `src/store/`
- **Domain separation**: one store per UI concern (e.g., `theme-store.ts`, `nav-store.ts`)
- **Granular selectors**: always select only what you need to avoid unnecessary re-renders
- **Actions**: define state updates as named actions inside the store, not in components

**FORBIDDEN in Zustand stores:**

- ❌ Server/API state → use TanStack Query
- ❌ Auth session → no auth in this repo
- ❌ Per-component state → use local `useState` in the hook
- ❌ Direct state mutation from a component (use store actions)
- ❌ Mixing UI state and business logic in the same store property

### B3. Migration Steps

1. **Identify**: confirm the state qualifies (shared across unrelated components or truly global UI)
2. **Create store**: in `src/store/[domain]-store.ts` using Zustand
3. **Define selectors**: granular, one value per selector
4. **Define actions**: named functions that update state
5. **Refactor hook**: replace local `useState` with store selector + action
6. **Refactor component**: ensure component only receives values from the hook — no direct store access from components

### B4. Checklist Before Marking Migration Complete

- [ ] Store only contains global UI state
- [ ] Components do not call `useStore` directly — they go through a hook
- [ ] Selectors are granular (not selecting the entire store object)
- [ ] No server state or business logic in the store
- [ ] Quality gates pass: `bun fl && bun type-check`
