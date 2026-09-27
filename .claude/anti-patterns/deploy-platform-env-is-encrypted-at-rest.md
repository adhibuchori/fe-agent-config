# A deploy platform that stores app env encrypted: never write it with SQL

**Applies to:** Changing the environment variables of an application on a self-hosted deploy
platform whose own database holds each application's env (the server behind
`.claude/mcp/deploy-platform.example.json` and `/promote-deploy`)
**Status:** Permanent while the platform encrypts that column

## Symptom

A direct SQL write to that column, such as an `UPDATE` that appends one variable, reports success
(`UPDATE 1`) yet can leave the column empty or unreadable, and the application's whole environment
configuration with it. The running container is unaffected, because it read a file written at
deploy time, so nothing looks broken until the next deploy.

## Root cause

The env column holds **ciphertext**, not text, typically with a version prefix:

```text
enc:v1:<base64>
```

Concatenating onto it produces garbage, and a `||` with a subselect that returns `NULL` sets the
whole column to `NULL`, silently, because SQL has no reason to object.

## Fix

Use the platform's API, which handles the encryption. Its "save environment" call typically:

- takes the **full** new value, not a delta: there is no append, so read the current value first;
- carries sibling fields in the same call (build arguments, build secrets, whether to write an env
  file); send back exactly what the read returned, or they are reset.

Do the read-modify-write **on the server**, not locally: the response contains every production
secret, and keeping it server-side keeps it out of the local machine and out of any transcript.

Take a snapshot of the stored value first. It is one command and it is the whole recovery path:
write it to a file only root can read, verify a restore by comparing a hash of the column, and
delete the snapshot securely afterwards.

An agent does not run that write: it prepares the new value and the command, and the user runs
them. Production env is the user's to change.

## The 401 that sends you down the wrong path

Calling the API with the key copied from the server's MCP config returns `401 Unauthorized`, which
reads as "the API is unusable" and makes direct SQL look like the only option. It is not: the value
in the config is a **reference** (`${DEPLOY_PLATFORM_API_TOKEN}`) resolved from the user's shell
environment when the server starts. The literal string is not the token.

## Also worth knowing

- Saving env only stores it; the running container keeps the old values until a redeploy.
- A service reached by internal hostname on the platform's network has an address, not a secret:
  it belongs in the committed `.env.production.example`, not only in the live env.

## Scope

Any platform that encrypts per-application config at rest. Check the column's first bytes before
any SQL near it; a version prefix means the database is not the interface.
