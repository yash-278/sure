# Sure ChatGPT adapter

Private HTTP adapter for the pinned Codex App Server, using device-code login
and the connected account's subscription allowance. Node 24 runs the TypeScript
sources directly. No OpenAI API key is required or used.

## Deployment

Deploy this directory as a private Railway service. Set `ADAPTER_TOKEN` to a
random secret of at least 32 characters, `CODEX_HOME=/data/codex`, and `PORT=3000`.
Mount a persistent volume at `/data`. Use `/health` as the health-check path.
Do not provision a public domain. Web and worker services need:

- `CODEX_ADAPTER_URL=http://codex-adapter.railway.internal:3000`
- `CODEX_ADAPTER_TOKEN`, referencing the private service's `ADAPTER_TOKEN`
- `CODEX_OWNER_USER_ID`, the immutable Sure user UUID
- `CODEX_OWNER_FAMILY_ID`, the immutable family UUID

Enable preview features for that owner, then open Settings > Hosting > ChatGPT
connection. Complete the device login personally, select the account default or
an advertised model, and save. The owner must also have Sure AI consent enabled.
Other users cannot manage or use the connection.

The adapter image pins `@openai/codex@0.154.0`. Upgrades require repeating the
login, structured-output, image, persistence, logout, and quota checks.

## Internal protocol

All routes except `GET /health` require `Authorization: Bearer <ADAPTER_TOKEN>`.

| Route | Operation |
| --- | --- |
| `GET /account` | Sanitized connected-account metadata |
| `DELETE /account` | Cancel work and log out through Codex |
| `POST /login` | Start device-code login |
| `GET /login` | Login progress and pending verification code |
| `DELETE /login` | Cancel pending login |
| `GET /models` | Advertised model catalog |
| `GET /limits` | Subscription quota information, never API prices |
| `GET /settings`, `POST /settings` | Read or set `{paused: boolean}` |
| `POST /operations` | Submit `{id, prompt, schema, model?, images?, priority}` |
| `GET /operations/:id` | Retrieve saved status and validated-by-Rails result |
| `DELETE /operations/:id` | Cancel queued or active generation |

Priority is `interactive` or `background`. Image inputs are data URLs. Only one
generation runs at a time. Interactive requests precede queued background work.
Pause does not interrupt an already running request. Disconnect cancels work.

Operation IDs bind to the entire request digest. Reusing an ID with different
input is rejected; completed results survive restarts. Prompts are not stored in
operation files. Unfinished work at restart is marked interrupted and never
silently replayed. Quota waits retain queued work and resume after the reset.
Rails retains paused background jobs, resuming them when the owner saves the
connection settings or the quota reset job runs. A generation interrupted after
starting needs explicit investigation before a new operation is issued.

Codex host tool requests are denied. Shell, patch, browsing, MCP servers and apps
are disabled for generation. Rails validates answer/function JSON and executes
its existing permission-scoped financial tools. Financial tool results are
recorded under a stable request key to avoid duplicate writes. Replacing an
existing valuation requires approval bound to the stored arguments.

Statement extraction uses local page text or rendered page images. It preserves
decimal strings and page references, rejects ambiguous dates and currencies,
and flags balance discrepancies and repeated rows. Existing import review and
reconciliation remain responsible for publishing. Document search is unavailable
with this provider; no embedding or vector-store API is called.

## Operations and recovery

Keep `/data` private and persistent. Codex manages credentials under `CODEX_HOME`;
never copy tokens into Rails settings, logs, Git, or planning notes. Back up the
Sure database before applying the additive approval, execution and deferred-job
migrations. Keep subscription usage separate from API cost reporting.

Rollback by pausing background AI and disabling the preview provider. Preserve
the additive tables and financial records. Do not change provider selection to
an API provider as part of automatic recovery.

## Tests

Run `node --test *.test.ts` here and the repository's required Rails, system,
Ruby/ERB, Biome and Brakeman checks before publishing changes. Railway hosting
is billed separately from the shared Codex subscription allowance.
