# authoring codespace hooks (bootstrap · post-create · dev)

The contract for wiring a stack's repos so they provision + run in a remote
per-stack DinD **sandbox** and via `codespace dev` **locally and remotely** with
identical dev behavior. It is org-agnostic — the specifics (distro, runtimes,
package managers) are derived per stack from each repo's own setup, not baked in
here. `codespace prompt sandbox-bootstrap` emits a paste-ready agent prompt that
embeds this contract plus auto-detected facts about your repos.

The guiding principle: **mirror how a real developer sets each repo up** — the
repo's own `README` setup section, `Makefile`/`package.json` targets, and version
pins (`.python-version`, `.nvmrc`, `packageManager`, `Dockerfile*`, `Brewfile`)
are the maintained source of truth. Do NOT invent a parallel version list, and do
NOT base provisioning on an infra/IaC repo (that is production wiring, unrelated
to a dev environment).

---

## The three hooks

Hooks are resolved from the user config dir first
(`$CODESPACE_CONFIG_ROOT/<org>/<repo>/`, `.codespace/` subdir preferred over the
config-dir root), then from a repo-committed `<repo>/.codespace/`. All hooks must
be **idempotent** (re-runnable on an existing sandbox).

### 1. `remote-bootstrap.sh` — system provisioning (remote only)

Two levels:

- **org/stack-common** (`<stack-config>/.codespace/remote-bootstrap.sh`, next to
  `stacks.json`): runs **ONCE, serially, before** the parallel per-repo jobs.
  **This is the ONLY safe place for system installs** (the sandbox distro's
  package manager — `apt`/`dnf`/`apk`/… — language-runtime installers, corepack
  activate, adding a `docker-compose` shim) — they mutate shared host-global
  state and would race the package-manager lock if run from the parallel per-repo
  hooks.
  Env: `CS_STACK_REPOS` (csv), `CS_STACK_NAME`, `CS_STACK_BRANCH`,
  `CS_STACK_CONFIG_DIR`, `CS_SANDBOX`, `CS_REMOTE_CODESPACE=1`.
  Gate each install on the repos actually present, e.g.
  `case ",$CS_STACK_REPOS," in *,core,*) ... ;; esac`.
  The repos are **not cloned yet** at this point, so key off repo **names** (from
  `CS_STACK_REPOS`), not on-disk files.

- **per-repo** (`<repo>/.codespace/remote-bootstrap.sh`): runs **in parallel**,
  once per repo, in the worktree. Env: `CS_HOST`, `CS_REPO_ID`, `CS_BRANCH`,
  `CS_REMOTE_PATH`, `CS_REMOTE_BASE_REPO`, `CS_POST_CREATE_CONFIG_DIR`. Keep it
  free of system-package installs (use org-common). Often unnecessary — omit it
  and provisioning falls through to org-common + post-create. (A well-factored
  setup usually has **no** per-repo bootstrap: everything shared lives in
  org-common.)

Reproduce the repo's own recipe for the sandbox's distro: translate a
host-specific `setup-system` layer (e.g. `brew`/`pyenv`) into that distro's
package-manager equivalent, using the repo's OWN pins — its `Dockerfile*` install
lines, its `Makefile`/README version pins, `.python-version`,
`.nvmrc`/`packageManager`. **No per-project runtime managers** (mise/asdf/nvm) —
install the runtime so it is plainly on `PATH`.

### 2. `post-create` — dependency install (local AND remote)

Runs in the worktree after clone/sync. Must run **identically** on the laptop and
in the sandbox: invoke the repo's OWN deps command (`make install`,
`pnpm install`, `npm i`, `poetry install`, …). `CS_REMOTE_CODESPACE=1` is set on
the remote; use it only for the OS/system layer, not the deps layer:

- **remote**: the system layer was already handled by org-common bootstrap — just
  install deps.
- **local (mac)**: if a required runtime is missing, **print an "install X"
  instruction and stop** — do NOT auto-install (no `brew install` behind the
  dev's back). If present, install deps the same way as remote.

Helpers (run via `codespace ...`, already on `PATH`):
`codespace post-create.link-files-from-repo <files...>` and
`codespace post-create.link-files-from-config <files...>` link untracked files
(e.g. `.env`, `AGENTS.md`); on the remote they verify the create flow shipped
them. `codespace hide <file>` git-excludes a provisioning artifact.

Provisioning only. Bringing databases up + migrations are **run-time** concerns
owned by `dev`.

### 3. `dev` — run the project (local AND remote, byte-for-byte identical)

`codespace dev` executes this in a tmux window whose cwd is the worktree — locally
on your laptop, or in the sandbox for a remote/synced stack (`-r` provisions +
syncs first if absent). **The same script runs in both**; only the transport
differs (localhost vs `ssh -L` + Caddy `https://{slug}.localhost`). Therefore:

- **No runtime activation inside `dev`** (no `mise activate`, `nvm use`, venv
  `activate`). Whoever provisioned the env put the toolchain on `PATH`; `dev` just
  runs. (For poetry, call `poetry run …` / `make <target>` that wrap it, so no
  venv activation is needed.) Prepending `$HOME/.local/bin` to `PATH` is a safe,
  portable no-op.
- **Announce ports** so the client can forward them:
  - preferred static declaration in `stacks.json` `dev` map (see below) or a
    `# CS_DEV: web=3000:https api=8000` comment line in the dev script — these are
    forwarded **immediately** (no manifest wait).
  - dynamic/runtime ports: `codespace-cloud dev manifest-add --label <l> --port
    <p> [--scheme http|https]` (race-free; one fragment per service). Announce
    up-front, before slow startup, so the client forwards while services boot.
- **Foreground the long-running process** (`exec make api`, `exec pnpm dev …`) so
  the tmux window stays alive. Disable interactive TUIs that fight tmux (e.g.
  turbo `--ui=stream`); prefer `--continue`-style flags so one failing service
  doesn't tear the rest down.
- **Idempotent**: `docker compose up -d`, readiness gates, migrate-once.

The inner Docker daemon (DinD) is ready before ssh is advertised; if a service
needs compose, additionally gate on `docker info` in bootstrap. Note some
Makefiles call the v1 binary `docker-compose`; the sandbox ships compose v2
(`docker compose`) — add a `~/.local/bin/docker-compose` shim in org-common if so.

---

## `stacks.json` dev/ports

```jsonc
{
  "dev": { "web": 3000, "api": 8000 },        // flat form (label: port)
  // or the structured form with a manifest-wait budget (seconds):
  "dev": { "timeout": 300, "ports": { "web": 3000, "api": 8000 } }
}
```

`web` defaults to `https`, everything else to `http`. Static ports forward
immediately; the manifest is only waited on for purely-dynamic ports. Wait budget
precedence: `--timeout` > `$CS_DEV_TIMEOUT` > `stacks.json` `dev.timeout` > 300.

---

## Acceptance checks

1. `codespace stack create <branch> -r --dev` provisions the sandbox and brings
   every service up with **no** per-project runtime manager anywhere.
2. `codespace dev` (local, in an existing stack) runs the same hooks and reports
   `http://127.0.0.1:<port>`.
3. `codespace dev -r` provisions+syncs a missing remote, then runs there and
   forwards `https://{slug}.localhost`.
4. `codespace dev status` shows the running services; `codespace dev stop` tears
   the session + tunnels + routes down.
5. Re-running any hook on an existing sandbox is a no-op (idempotent).
