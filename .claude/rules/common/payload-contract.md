---
paths:
  - 'src/lib/payload/**'
  - 'src/lib/api/**'
  - 'src/app/api/**'
  - 'scripts/check/endpoints.ts'
  - 'scripts/check/crypto-interop.ts'
  - 'scripts/generate/endpoints.ts'
  - 'payload.config.json'
---

# Payload Contract (short form)

Bodies that cross a service boundary travel sealed; every route is in one registry with its policy.
The full contract, threat model and wiring: `.claude/PAYLOAD-CONTRACT.md`.

- **Strict unless exempted.** A route leaves `strict` only through `payload.config.json`
  `exemptions`, with a reason. Pick a half-policy by what the body needs (`response-only` for a
  multipart upload, `request-only` for an event stream or a browser-saved file), never by how
  sensitive it looks.
- **No route literal outside the registry**: take paths from `ENDPOINTS` (`pathOf`). Never edit
  `endpoints.generated.ts`; run `bun run generate:endpoints` after the spec changes.
- **Encrypt at the transport only.** Components, hooks, handlers, services and schemas never import
  `src/lib/payload/` (or `app.core.payload`). No `fetch` outside the transport.
- **Read the raw request once** and replay plaintext (Hono: `c.req.raw.text()`, never `c.req.text()`;
  ASGI: one replayed message, then the server's own `receive`).
- **Keys are added, never repurposed**; never `NEXT_PUBLIC_`; rotation is `<NAME>_NEXT`. Never
  print, log or commit a key; tests use placeholder bytes.
- **Never log a sealed body's plaintext.** Log the code, pattern, `kid` and request id.
- **Refusals leave in plaintext** problem+json with a `ENVELOPE_*` code; a plaintext success on a
  sealed route is a downgrade.
- **Tests go through the real cipher**, and the shared vectors are never regenerated to pass.
- **Do not call it end-to-end encryption** on the browser hop: the browser holds the key.
- **The switch stays `strict` in the committed file**; debug with `PAYLOAD_MODE=off` in
  your own shell. Gates: `check:endpoints`, `check:crypto-interop` (TypeScript), `pytest` (Python).
