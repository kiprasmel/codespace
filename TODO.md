# TODO

## done

- [x] `codespace sync` — mirror a local codespace to a remote ssh host, re-runnably
  - [x] commit-granular, bidirectional integration; local is the main when histories diverge (ff/rebase, then align the remote; `--force` resets the remote to local HEAD with a backup ref)
  - [x] uncommitted changes resolved up front: `--commit [-m]` / retry / `--uncommitted [--once]` one-shot overlay (gitignore honored; remote must be clean)
  - [x] first sync provisions the remote (reuses the create machinery); target remembered in a git-excluded `.codespace/sync` marker
  - [x] stacks: whole-stack sync (host prepared once, each repo commit-synced independently, loose root files rsync'd, per-repo conflicts reported)
  - [x] persistent live (uncommitted) sync via optional `mutagen` (`--watch` / `--stop`, foreground or `--detach`, gitignore-aware); commits ride a HEAD poll (no hooks); commit-during-live (incl partial) loses nothing; conflicts surfaced
  - [x] `codespace open -r [host]` opens a local codespace's remote counterpart, syncing it first (live)
  - history moves over plain ssh (local fetches the remote worktree; canonical tip handed over via a holding ref the remote reconciles onto)

- [x] list command to list codespaces of current repo (`codespace ls` / `list`)
  - [x] print on-demand as found (streams each row; lazy per-section headers)
  - [x] finds remote ones too (via local `.codespace-remote` stubs; no ssh needed)
  - lists this repo's worktrees/clones/remote stubs first, then a separate section of stacks containing the repo
  - reuses `codespace stack ls` helpers; flags: `-q`, `--older-than`, `--by-commit-age`, `-i/--integrated`, `--rm`

- [x] support stack-post-create.sh command - defined next to stacks.json.
  - [x] should receive stack name etc as defined env vars
  - [x] should run at same time as the post-create scripts of repos (i.e. not after them, in parallel rather).
  - [x] sample use cases: create/copy files with predefined content

- [x] when creating a codespace, regardless if worktree or stack: if a provided branch name already exists in repo (even if only in remote), we should use it, instead of creating a new one from scratch

- [x] i want to be able to run the stack-post-create command in an existing stack, just like i can already run the post-create for a regular (non-stack) codespace

- [x] detect & use repo-committed `.codespace/` folder and org-committed `stacks.json` / `.codespace/stacks.json`
  - user-level config in `$CODESPACE_CONFIG_ROOT` still takes precedence when present
  - tool prints a note of the chosen path, and if both user + committed exist, notes the ignored one
  - for the repo's post-create script, the active config dir is exported as `$CS_POST_CREATE_CONFIG_DIR` so helpers (e.g. `link-files-from-config`) resolve relative to it
  - stacks.json lookup order at each walk-up level:
    1. `$CODESPACE_CONFIG_ROOT/<rel>/.codespace/stacks.json`
    2. `$CODESPACE_CONFIG_ROOT/<rel>/stacks.json`
    3. `<dir>/.codespace/stacks.json`
    4. `<dir>/stacks.json`

## todo

- [ ] work out the "--bare" repo setup & confirm works
- [x] test (bats?) to confirm behavior works / avoid regressions
  - vendored bats-core + helpers under `test/vendor/` (run `./test/setup.sh` once)
  - `./test/run.sh` runs the suite
  - covers: `cs_stack_find_in_dir`, `cs_stack_resolve_config_at`, `cs_stack_find_config` walk-up, `cs_resolve_post_create`, and end-to-end `cs_post_create` (including `CS_POST_CREATE_CONFIG_DIR` export and `link-files-from-config` helper)

- [ ] post-create.hidden-remove-local-files
  - e.g., if a project has a global & committed CLAUDE.md, but i don't like it, and don't want to modify it either
  - so instead i just want to remove it, and if i want to, i'll create one myself, or copy & edit to my liking, and store in layer2 (config dir)

- [ ] (?) rename stack create -s to -c (from stack-name to stack-config, to avoid mixing up with the stack name (branch))

- [ ] working globally, not inside some directory
	- [ ] codespace create - from anywhere. select which repo / auto infer where from, via cli arg
	- [ ] same for stack create
	- [ ] `find` should work globally too

- [ ] "stack create -s" should handle repo names as stack configs, just like stack extend

- [ ] README should have sample layer2 config after codespace -h

- [ ] git command proxy - some commands should work for multiple repos
  - e.g. "git status"
	- maybe assume like we're in a monorepo & subrepos are just folders?
	- or, simply apply the command in each repo and combine results
      - obv cannot do this for all commands. but simple stuff would be nice

- [ ] need to describe clearly how to setup CODESPACE_CONFIG_DIR, where to place what files (/org/repo/.codespace/post-create, /org/stacks.json, /org/.codespace/stacks.json)

- [ ] when creating a stack, if a branch of a repo already exists in remote, we fetch it. but it seems like we skip running the setup (e.g. post-install script)?

- [x] alias "open" to "edit"
  - `codespace open [branch|path]`: no arg opens the codespace at cwd, a path opens
    that codespace, a branch behaves like `edit`. handles remote codespaces.
  - every codespace root (local + remote stub) gets a generated `./open` script.

- [ ] rename "stack_name" to "stack_config", to avoid confusion between an actual stack where repos are held, vs the stack config name inside stacks.json
  - [ ] -s flag too?

- [ ] stack-post-create should probably run everything that's done after a stack is created, instead of just the stack-post-create.sh script
  - post-create scripts of each repo
  - stack-post-create.sh script
  - other setup logic etc, basically everything that's done after creation (hence, "post-create")
  - idk if needs differentiation from the "just the script" case

- [ ] cleanup --help stuff. e.g. main codespace --help shouldnt need to list optional flags of specific subcommands, etc
	- [ ] same when documenting subcommands - shouldn't need to list all options, etc - should offer a simplified overview, w/ expectation that user can inspect further via specific subcommand's --help

- [x] sync --watch doesn't seem to work at all? exits immediately after done
  - `--watch` now stays active in the foreground until stopped/killed (Ctrl-C
    terminates the session), engaging even on a clean tree so it waits for
    changes. `-w` aliases `--watch`; `-d`/`--detach` keeps the old return-now
    behavior; `--stop` aliases `--stop-watch`.

- [x] in codespace sync, split & describe the commits-only vs uncommitted-changes-too syncing
	- [x] `dirty` (uncommitted + commits) is the default — a full proper sync; `commits` for history only
	- [x] one `-m`/`--mode dirty|commits` flag (arg aliases `d`/`c`) instead of two flags
	- [x] all flags are mode-agnostic — `--ours`/`--theirs`/`--hard` and `--watch`/`--detach` work in both modes (the resolve is commit-level either way; dirty work is stashed around it, never discarded)
	- [x] `--ours`/`--theirs` are granular by default (rebase -X: keep both sides, resolve only conflicts); `--hard` is the wholesale-reset escape hatch
	- [x] help reworked: tight top description + flat flag list + a dedicated `--ours`/`--theirs`/`--hard` section

- [ ] describe behavior/learning flow of the codespace tool, the use-cases, how to "reinvent yourself" / why each part was created / what problem it solves
	- [ ] first - simple git worktree wrapper
	- [ ] then, stacks: groups of worktrees commonly used together
	- [ ] then, remote connectivity: creating codespaces/stacks in remotes (vps, another PC at home, etc)
	- [ ] then, sync: agent works locally (no need to mess w/ credentials in remotes), but is able to run & test projects in the remote.
		- [ ] win for local laptop - less mem usage, less battery drain, less hot fingers
		- [ ] automatic 2-way sync, primarily with commits, but also handles uncommitted changes well.
	- [ ] then, eventually: agent fully works in remote, user is able to connect, conduct, etc, but minimal load on their local laptop
		- [ ] can still use it via 2-way sync
		- [ ] can technically be done already via sync and running CLI-based agent harness, but as i use cursor myself, it's UI cannot fully run in the remote and be a smooth experience (e.g. agent fully working even if laptop is off), since it's still running locally, just connecting to a remote.
