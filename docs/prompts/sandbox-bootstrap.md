You are wiring the repositories of the **{{STACK_LABEL}}** stack so they provision
and run inside a remote per-stack Docker-in-Docker **sandbox**, and via
`codespace dev` **both locally and remotely with identical dev behavior**.

Author (or update), for each repo below, under its codespace config dir
(`{{CONFIG_DIR}}/<repo>/.codespace/`, or the repo-committed `<repo>/.codespace/`):

- an org/stack-common `remote-bootstrap.sh` at `{{CONFIG_DIR}}/.codespace/`
  (shared **system** provisioning, runs once serially before the parallel
  per-repo jobs — the only safe place for system-package / runtime installs),
- each repo's `post-create` (dependency install, identical local + remote),
- each repo's `dev` (run the project; **byte-for-byte identical** local + remote),
- and the `dev` port map in `{{CONFIG_DIR}}/stacks.json`.

## Method (do this, in order)

1. **Learn each repo's OWN documented dev setup FIRST** — its `README` setup
   section, `Makefile` `setup`/`install` targets, `package.json` scripts, and
   version pins. That is the maintained source of truth. Do NOT invent a parallel
   version list, and do NOT base this on an infra/IaC/prod repo.
2. **Reproduce that setup for the sandbox's distro** — first find out what the
   sandbox base image is, then translate any host-specific `setup-system` layer
   into that distro's package-manager equivalent, using the repo's OWN pins
   (`Dockerfile*` install lines, `.python-version`, `.nvmrc`/`packageManager`,
   `Brewfile`). Put runtimes plainly on `PATH` — **no per-project runtime
   managers (mise/asdf/nvm)**.
3. Put every **system** install in the org-common bootstrap, gated on
   `CS_STACK_REPOS` (the repos aren't cloned yet there — key off repo *names*).
4. Make `post-create` install deps via the repo's OWN command, identically local +
   remote; on the laptop, if a runtime is missing, **instruct and stop** — never
   auto-install behind the developer's back.
5. Make `dev` run the project with **no runtime activation** inside it, announce
   its ports (static in `stacks.json`/`# CS_DEV:` or dynamic via
   `codespace-cloud dev manifest-add`), and foreground the long-running process.
6. Keep every hook **idempotent**.

## Detected facts (verify against the repos before trusting)

{{REPO_FACTS}}

## Acceptance

- `codespace stack create {{STACK_BRANCH_EXAMPLE}} -r --dev` provisions the
  sandbox and brings every service up with no per-project runtime manager.
- `codespace dev` (local) runs the same hooks and reports `http://127.0.0.1:<port>`.
- `codespace dev -r` provisions+syncs a missing remote, runs there, forwards
  `https://{slug}.localhost`.
- `codespace dev status` lists services; `codespace dev stop` tears everything down.
- Re-running any hook on an existing sandbox is a no-op.

---

# CONTRACT (the rules the hooks must follow)

{{CONTRACT}}
