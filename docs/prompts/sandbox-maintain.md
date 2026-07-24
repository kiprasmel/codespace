You are **maintaining** the codespace hooks for the **{{STACK_LABEL}}** stack so
they stay in sync as its repositories drift. The hooks — the org/stack-common
`remote-bootstrap.sh`, each repo's `post-create` and `dev`, and the `dev` port map
in `{{CONFIG_DIR}}/stacks.json` — **mirror each repo's own maintained setup**; they
are NOT an independent source of truth. Your job is to find where the repos have
moved ahead of the hooks and reconcile only that drift.

## Method (do this, in order)

1. **Re-read each repo's OWN setup** — its `README` setup section, `Makefile` /
   `package.json` targets, and version pins. This is the source of truth; the
   hooks must match it. Use `git log` / `git diff` since the hooks were last
   touched to see what actually changed (don't rewrite what hasn't drifted).
2. **Audit each hook layer for drift**, and fix only the layer that owns it:
   - **runtime / system** (org-common `remote-bootstrap.sh`): a bumped
     `.python-version` / `.nvmrc` / `packageManager`, a new install line in a
     `Dockerfile*`, a new system package or service dependency.
   - **dependencies** (`post-create`): a changed install command
     (e.g. `make install` → something else), a new install step. Keep it identical
     local + remote; on the laptop, instruct-and-stop for a missing runtime.
   - **run / ports** (`dev` + `stacks.json`): a new, renamed, or removed service;
     a changed start command or port; a new dynamic port to announce.
   - **stack membership**: a repo added to or removed from the stack — update the
     `CS_STACK_REPOS` gates in org-common bootstrap AND the `stacks.json` entries.
   - **idempotency regressions**: a hook that no longer re-runs cleanly on an
     existing sandbox.
3. **Change nothing that hasn't drifted.** Prefer the smallest edit that restores
   parity with the repo's own setup; do not invent a parallel version list.
4. **Re-verify** against the acceptance checks below (they must all still hold).

## Detected facts (current repo state — compare against the LIVE hooks)

{{REPO_FACTS}}

## Acceptance (must still hold after your changes)

- `codespace stack create {{STACK_BRANCH_EXAMPLE}} -r --dev` provisions the
  sandbox and brings every current service up with no per-project runtime manager.
- `codespace dev` (local) runs the same hooks and reports `http://127.0.0.1:<port>`.
- `codespace dev -r` provisions+syncs a missing remote, runs there, forwards
  `https://{slug}.localhost`.
- `codespace dev status` lists services; `codespace dev stop` tears everything down.
- Re-running any hook on an existing sandbox is a no-op.

---

# CONTRACT (the rules the hooks must follow)

{{CONTRACT}}
