# Payload Contract: Sealed Bodies and One Endpoint Registry

> On-demand reference: CLAUDE.md lists it and nothing imports it;
> `.claude/rules/common/payload-contract.md` loads the short form when you touch the transport, the
> registry or `payload.config.json`. The module is optional: a repo that does not adopt it follows
> the last section. The same file ships to every stack that speaks the format; keep the copies
> equal.

Every request and response body that crosses a service boundary is sealed in an envelope, and every
endpoint is declared in one registry per repo, with its encryption policy beside its path. Both
halves are enforced: at runtime by the transport, and before merge by `check:endpoints` and
`check:crypto-interop`.

## Threat model: say what it buys, and nothing more

A browser that seals its own requests does not hide them from the person using it. The key and the
code live in the page; a breakpoint shows the plaintext. Browser-side sealing buys:

- **Passive capture yields ciphertext**: a proxy log, a HAR file pasted into a ticket, an extension
  reading responses, the Network tab at a glance.
- **Integrity and binding**: an envelope opens only for the route, method (or status) and key it was
  sealed for, inside a two-minute window. Replaying it elsewhere fails.
- **Scraping and replay get expensive**, because every request needs a live key agreement.

Confidentiality still comes from TLS, httpOnly session cookies, a server-side proxy, a tight
`connect-src`, and no production source maps. **Never describe the browser hop as end-to-end
encryption.** Server-to-server hops are different: their keys never reach a browser, so sealing
there is real defence in depth when the hop crosses a network you do not own.

## Hops

| Hop                          | Keys                                                            | Where they live                        |
| ---------------------------- | --------------------------------------------------------------- | -------------------------------------- |
| Browser ⇄ frontend server    | ECDH P-256 per tab, HKDF-SHA-256 → AES-256-GCM; nothing static  | the server's keypair, server-only env  |
| Frontend server ⇄ backend    | a pre-shared AES-256 key, `kid:base64` in one variable          | both servers' env, never `NEXT_PUBLIC_`|
| Service ⇄ service            | one pre-shared key per hop, named after the hop                 | both services' env                     |

The browser sends its ephemeral public key in the `x-payload-epk` header of **every** request,
body or not: a GET has no envelope, and the server still needs the key to seal the response. The
server re-derives the key per request and stores nothing. Server callers name their key in
`x-payload-kid`, and a server seals its answer under the key the request used, so one service can
answer several callers holding different keys.

## Wire format

`Content-Type: application/vnd.payload-envelope+json`

```json
{ "v": 1, "alg": "A256GCM", "kid": "k1", "iv": "<base64url 12 bytes>", "ct": "<base64url>", "ts": 1767225600000 }
```

- `v`: an unknown version is refused, never guessed at. `alg`: only `A256GCM` in version 1.
- `kid`: the pre-shared key's id, or `ecdh` for an agreed key.
- `iv`: 96 bits, fresh for every encryption, never reused under a key.
- `ct`: ciphertext with the 16-byte tag appended (the layout WebCrypto and Python's
  `cryptography` both produce). `ts`: epoch **milliseconds** when sealed.
- **AAD**, never sent: request `1.<METHOD>.<pattern>.<kid>.<ts>`, response
  `1.<status>.<pattern>.<kid>.<ts>`. The pattern is the registry pattern (`/api/notes/:id`), not the
  URL, so both sides agree without sharing a URL normaliser. The accepted cost: inside the window an
  envelope can be replayed across ids of one route.
- **Freshness**: more than 120 s from the receiver's clock, either way, is refused, and checked
  before the cipher runs. This is not full replay protection; that needs a nonce store.
- **Status codes stay in clear** on the status line, so `!res.ok` and a sign-out on 401 work
  without decrypting. Error bodies are sealed like any other body.

## Policies

Every entry is `strict` unless it cannot be. A half-policy names the side that cannot be sealed, and
the reason is always a property of the body, never a judgement of how sensitive it is.

| Policy          | Request | Response | For                                                           |
| --------------- | ------- | -------- | ------------------------------------------------------------- |
| `strict`        | sealed  | sealed   | everything, by default                                        |
| `response-only` | plain   | sealed   | `multipart/form-data`: the boundary must reach the parser     |
| `request-only`  | sealed  | plain    | `text/event-stream`; a file a browser saves or an image it draws |
| `none`          | plain   | plain    | health probes, the spec, the handshake, a third party's webhook |

Choosing the wrong half-policy is silent: a stream marked `response-only` still works, it just stops
streaming. Transports call `sealsRequest` / `sealsResponse`; none compares policy strings. A
browser-saved file or an `<img src>` cannot open an envelope, so what protects it instead is a
short-lived signed link minted over a `strict` route. No body (204, 304) means nothing to seal.

## The rules

- **P1 Strict unless exempted.** A route leaves `strict` only through an entry in
  `payload.config.json` `exemptions` (`"METHOD /pattern": { "encryption", "reason" }`), which review
  sees. There is no per-call opt-out.
- **P2 One registry, no route literals elsewhere.** Backends: `src/lib/endpoints/`; frontends:
  `src/lib/api/endpoints/`. Code takes paths from the registry (`pathOf(ENDPOINTS.X, id)`), never a
  typed `'/api/...'`.
- **P3 The spec-derived half is generated.** `bun run generate:endpoints` writes
  `endpoints.generated.ts` from the spec and the exemptions. A policy typed into the output is
  reverted by the next run; decide it in the config.
- **P4 Encrypt at the transport, never in feature code.** Only the API client's transport, the
  proxy route and the boundary middleware import `src/lib/payload/`. Hooks, components, handlers,
  services and schemas see plaintext objects.
- **P5 An unregistered route is refused by a client.** `matchEndpoint` answering `undefined` means
  the transport refuses to send. A server passes it through, because its router answers 404 and there
  is no payload; `check:endpoints` keeps every real route registered.
- **P6 Keys are added, never repurposed.** A new variable per hop, never `NEXT_PUBLIC_`, never an
  auth library's secret. Rotation adds `<NAME>_NEXT`: both sides accept either, only the first seals;
  deploy both, then swap.
- **P7 An exemption needs a written reason**, and a strict entry carries none.
- **P8 Read the raw request once.** A middleware reads the body from the raw request (`c.req.raw` in
  Hono), never through a cache a validator reads later, and replays it as plaintext. ASGI: replay one
  message and hand every later `receive()` to the server; never invent `http.disconnect`.
- **P9 Tests go through the real cipher.** A route or transport test seals and opens real envelopes;
  a double that accepts plaintext proves nothing about the contract.
- **P10 Never log what was sealed.** Log the code, the route pattern, the `kid` (public) and a
  request id. Never a plaintext body, a key, an envelope's decrypted content or the derived key.

## Refusals and error codes

| Code                    | Meaning                                                        |
| ----------------------- | -------------------------------------------------------------- |
| `ENVELOPE_REQUIRED` | a sealed route received plaintext: nearly always a hand-rolled call |
| `ENVELOPE_MALFORMED`  | an unknown version, a missing field, plaintext that is not JSON |
| `ENVELOPE_EXPIRED`         | outside the window: a replay, or clocks that drifted           |
| `ENVELOPE_KEY_UNKNOWN`   | a `kid` this side does not hold: mid-rotation or a bad deploy  |
| `ENVELOPE_REJECTED`   | the tag did not verify: tampering, the wrong key, another route |

A refusal raised by the payload layer leaves as **plaintext** problem+json (a 400, or a 500 when a
server cannot seal its own body), with the code and never a payload: the caller may hold no working
key. A client accepts a plaintext body only with a failure status or an empty body; a plaintext
success on a sealed route is a downgrade and is refused. After `ENVELOPE_REJECTED` a browser
drops its agreed key and negotiates again: that is what a server restarted with a new keypair
looks like. Add the codes to the backend's problem-code list and the frontend's error map.

## The switch

`payload.config.json` `encryption` is `strict`, committed. `PAYLOAD_MODE=off` in your own
shell turns the boundary off to bisect a transport problem locally. Three things keep `off` out of
production: every service refuses to start with `off` in production; `check:endpoints` fails when
the committed file says anything but `strict`; and a deployment can set
`PAYLOAD_MODE=strict`, which wins over the file. A browser never reads either source:
the handshake answers `{ publicKey, mode }`, and anything but an explicit `off` means strict.

## Keys: generate on your machine, never in a transcript

Placeholders only; real values go straight into the env file through the kit's unlock flow, which
masks them (`docs/unlock.md`):

```bash
# a pre-shared AES-256 key for one hop, set on BOTH sides of it (after `unlock env`)
printf 'k1:%s' "$(openssl rand -base64 32)" | bash scripts/env/set.sh .env.development PAYLOAD_KEY
```

A frontend server's ECDH keypair (`PAYLOAD_SERVER_JWK`, base64url JWK text) comes from
`generateServerKeyJwk()` in `src/lib/payload/ecdh.ts`, piped the same way. Never print a key, commit
one, or paste one into a chat. Test code uses obvious placeholder bytes, never a real key.

## Tests and interop

Each repo carries its own copy of the implementation, so copies can drift while each passes its own
suite. `scripts/check/payload-vectors.json` is the shared known-answer set: the AAD strings, the
ciphertexts to open, and the replays to refuse. Every implementation proves itself against it (the
unit test and `check:crypto-interop` in TypeScript, `test_vectors.py` in Python). Never regenerate
the vectors to make a failing copy pass. Name the other repos in `payload.config.json` `peers`
(`{ "name", "root" }`, a relative path) and the checks also compare the spec copy, the exemptions,
the constants, and seal with one copy and open with the other, both ways, when the peer is checked
out beside this repo; a peer that is not is reported as skipped.

## Wiring it in

- **Backend (Hono)**: `app.use(createPayloadMiddleware({ mode, registry: ENDPOINTS, prefixes:
  ENDPOINT_PREFIXES, keyRing }))` after the body limit, rate limit and timeout, before the routes.
  Build `mode` with `resolveEncryptionMode(env.PAYLOAD_MODE, config.encryption,
  isProduction)` and the ring with `createKeyRing([{ value: env.PAYLOAD_KEY, name:
  'PAYLOAD_KEY' }, …_NEXT])`, once, in the env module's orbit. A browser calling the backend
  directly needs `browserKeyPair` and a `GET` handshake route registered `none`.
- **Frontend (Next.js)**: the API client's transport calls `createBrowserPayload({ handshakeUrl })`
  once, then `seal` before each request and `read` after it; a registry miss is refused. The
  handshake route answers `{ publicKey, mode }` with `cache-control: no-store`. The proxy route uses
  `openFromBrowser`, `sealForUpstream`, `openFromUpstream` and `sealForBrowser` from
  `src/lib/payload/bridge.ts`, in a `server-only` module that reads the keys.
- **Python service**: `app.add_middleware(PayloadMiddleware, mode=…, registry=ROUTES,
  key_ring=…)` added first, so it runs innermost; a test walks `app.routes` and fails on a route the
  registry lacks. Add `cryptography` to the project's dependencies.

## Out of scope, on purpose

A framework that generates its own catch-all routes (a headless CMS admin, an auth library's
handler) is covered by a prefix rule, not an enumeration: a hand-written list would silently exempt
every route a future upgrade adds. A repo with no transport of its own (a static site, a CLI that
only reads) does not adopt this contract: delete `payload.config.json`, the payload module and its
tests, the endpoint registry and its scripts, their `gates.list` lines, the payload rule, AGENTS.md
§P and this file.
