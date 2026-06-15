# codespace

git worktrees, with convenience.

<!-- 
NOTE: THIS FILE IS AUTO-GENERATED. DO NOT EDIT MANUALLY.

EDIT gen.README.md.sh instead.
-->

## features

- post-create scripts
  - install dependencies, link files, etc
- simple setup for storing files outside main repository (e.g. AGENTS.md with your preferences)
  - while still tracking in git, just in a separate repo

## use-cases

- working on multiple features at the same time
- reviewing PRs locally
- running multiple agents in parallel on the same task, comparing output, picking best results
- fast iteration in feature-based development
  - customizable pre-defined stacks of repositories to create codespaces from
  - work in parallel on different features
  - shared context for agents - access to all repos involving a feature
- ...

## setup

by default, will install to `$HOME/.local/bin/`:

```sh
./install.sh
```

or, custom prefix (results in `/usr/local/bin/`):

```sh
PREFIX="/usr/local" ./install.sh
```

#### recommended aliases

```sh
git config --global alias.cs "\!codespace"
```

## usage

### codespace

```console
$ codespace -h

Usage:
codespace <branch> [-b base] [-r [host]] [--clone [clone_url]] [--no-edit]
codespace <sub-command>

  <branch>  can be existing (won't modify), or new (will create).

optional flags:
  -b, --base <branch>
            base branch to create from (default: remote HEAD).
  -r, --remote [host]
            create the codespace on a remote ssh host instead of locally.
            if [host] is omitted, resolves from $CS_DEFAULT_REMOTE, then
            $CODESPACE_CONFIG_ROOT/<repo-id>/.codespace/remote (per-repo),
            then $CODESPACE_CONFIG_ROOT/<rel-org>/.codespace/remote (per-org).
            layout mirror: $HOME/X -> remote:$HOME/codespace/X.
            a thin local stub at the usual local path tracks the remote
            codespace for find/edit/rm.
            files declared via post-create.link-files-from-{repo,config}
            (e.g. .env, AGENTS.md) are auto-shipped to the remote worktree
            from the local sources at create time. discovery runs the
            local post-create in a /tmp sandbox with CS_REMOTE_FILE_COLLECT=1.
            see also: .codespace/remote-bootstrap.sh (host-level setup hook).
  --clone [clone_url]
            create a standalone clone instead of a worktree.
            benefits: allows other checkouts/rebases in main repo,
            better for one-off initialization on remote systems.
            [clone_url] - inferred from remote if inside a git repo.
  --no-edit
            skip opening the new codespace/stack in an editor.
            applies to worktree, stack, and the <branch> shortcut.
            (also implied by $CS_NO_EDIT or $CS_NO_INTERACTIVE)


env vars:
  GUI_EDITOR or EDITOR  - for opening a newly created codespace in an editor.

  CODESPACE_CONFIG_ROOT - dir where user-level configs for codespaces are placed.
                          used to configure post-create scripts, link hidden files, etc.
                          layout of the dir should be: "/org/repo/" (see also base-repo).
                          inside:
                            - files, scripts, etc that are not in the repo itself.
                            - ".codespace/post-create" script - ran on codespace creation.
                            - ".codespace/remote-bootstrap.sh" - host-level setup for -r.
                            - ".codespace/remote" - default ssh target (one line).

                          post-create lookup order (first hit wins):
                            1. $CODESPACE_CONFIG_ROOT/<org>/<repo>/.codespace/post-create  (user)
                            2. <repo>/.codespace/post-create                               (committed in repo)
                          the tool prints a note with the path used (and any ignored).
                          the active config base dir is exported to the script as
                          $CS_POST_CREATE_CONFIG_DIR so helpers like
                          post-create.link-files-from-config resolve against it:
                            - user-level: config root ($CODESPACE_CONFIG_ROOT/<org>/<repo>/)
                            - repo-committed: <repo>/.codespace/

                          remote-bootstrap.sh runs ON THE REMOTE before post-create
                          (when -r/--remote is used). same lookup precedence as
                          post-create. always runs; idempotency is its job.
                          gets these env vars: CS_HOST, CS_REPO_ID, CS_BRANCH,
                          CS_REMOTE_PATH, CS_REMOTE_BASE_REPO,
                          CS_POST_CREATE_CONFIG_DIR.

  CS_DEFAULT_REMOTE     - default ssh target for -r/--remote when no host given.
                          overridden by an explicit host arg or .codespace/remote file.

  CS_NO_INTERACTIVE     - if set, skip interactive prompts and use defaults.
                          inferred if CURSOR_AGENT or CI is set.
                          implies CS_NO_EDIT.

  CS_NO_EDIT            - if set, skip opening the new codespace/stack in an editor.
                          same effect as --no-edit.

  CS_NO_FETCH           - if set, skip fetching remote before creating worktree.
                          by default, fetches the base branch before creating.

  CS_DEFAULT_CREATE_TYPE
                        - what 'codespace create' defaults to.
                          "worktree" (default) or "stack".

  DEBUG                 - if set, prints every command executed.


.git files / markers:
  CODESPACE_IS_CLONE    - marker file created in .git/ when using 'create' with '--clone'.
  .codespace-remote     - local stub marker for a remote codespace (created by -r).
                          contains: host, relpath, kind, repo_id, branch.
                          the local stub dir is otherwise empty; the real codespace
                          lives at remote:$HOME/<relpath>.
  .codespace/current    - marker at a codespace root (written by 'mark-current').
                          contains: path, branch, kind, [task], created.
                          git-excluded so it doesn't trip rm safety checks.
  open                  - executable convenience script written at every codespace
                          root (local + remote stub). runs 'codespace open' on its
                          own dir to (re)open the codespace in an editor. for local
                          worktrees/clones it's git-excluded so it won't show as
                          untracked.


sub-commands:
  c, create   <branch> [-b base] [-r [host]] [--no-edit]
                                - alias for worktree or stack create.
                                  (see CS_DEFAULT_CREATE_TYPE, default: worktree)
  wt, worktree [create] <branch> [-b base] [-r [host]] [--clone [url]] [--no-edit]
                                - create a single-repo codespace (worktree or clone),
                                  optionally on a remote ssh host (-r).
  s, stack    [create] <branch> [-r [host]]
                                - create a multi-repo codespace (stack).
                                  see 'codespace stack --help' for details.
  post-create [cs_path]         - run the post-create script for a given codespace.
                                  [cs_path] defaults to codespace inside cwd.
  rm, remove  <branch|path>     - remove a codespace (worktree or clone).
                                  checks for uncommitted/unpushed changes before removing.
                                  [-f, --force] - ignore safety checks.
  ls, list    [-q] [--older-than <dur>] [-i] [--rm]
                                - list this repo's codespaces (worktree/clone/
                                  remote), then stacks containing it.
                                  see 'codespace ls --help' for details.
  find        <branch>          - find codespace/stack path by branch name.
  edit        <branch>          - find codespace/stack and open in editor.
  open        [branch|path]     - open a codespace in editor (alias for edit).
                                  no arg opens the codespace at the current dir;
                                  a path opens that codespace; a branch finds it.
                                  remote codespaces open over ssh-remote.
                                  every codespace root also has a generated
                                  ./open script that runs this for you.
  mark-current [task]           - write a .codespace/current marker at the current
                                  codespace root (path/branch/kind[/task]) so agents
                                  know where they are. git-excludes the marker.
  current     [key]             - print the current codespace's .codespace/current
                                  marker (walks up). [key] prints one field (e.g. path).
  config                        - absolute path of config dir of the repo
  config init                   - init config dir + post-create script for current repo.
  repo-id     [rel_to]          - get the repo ID to locate appropriate config location
                                  in "$CODESPACE_CONFIG_ROOT".
                                  assumes that repositories are placed in "$HOME/org/repo"
                                  (controllable via [rel_to], which defaults to "$HOME").
                                  extracts "/org/repo" portion of "$PWD" wrt [rel_to].
  base-repo                     - absolute path to the root of the base repository.
  cleanpath   <string>          - sanitize path for worktree dir (replace /, :, spaces etc)
  is-checkout-not-worktree      - prints 1 if we are in a branch checkout in the main repo,
  hide     <file> <file2>...    - add file(s) to .git/info/exclude (local gitignore).
                                  note: affects not only the worktree, but the base repo.
```

### codespace stack

```console
$ codespace stack -h

Usage:
codespace stack [create] <branch> [-s stack_name] [-b base] [-r [host]] [--clone|--worktree] [--no-edit]
codespace stack init [<path>]
codespace stack extend <name>[,<name2>]...
codespace stack ls [-g|--global] [-i|--integrated] [-S|--size] [--no-gh]
                   [--older-than <duration>] [--by-commit-age] [--rm] [-q|--quiet]

  <branch>       branch name to create across all repos in the stack.
  <name>         stack config name from stacks.json, or repo name from org directory.

optional flags:
  -b, --base <branch>
                 base branch to create from (default: remote HEAD).
  -s, --stack <stack_name>
                 stack config name from stacks.json (default: "default").
  -r, --remote [host]
                 create the stack on a remote ssh host instead of locally.
                 if [host] is omitted, resolves from $CS_DEFAULT_REMOTE / config.
                 layout mirror: $HOME/X -> remote:$HOME/codespace/X.
                 a thin local stub at the usual local path tracks the remote stack.
  --clone        force clone mode (fresh clones for all repos).
  --worktree     force worktree mode (create worktrees from local repos).
  --no-edit      skip opening the new stack in an editor.
                 (also implied by $CS_NO_EDIT or $CS_NO_INTERACTIVE)


env vars:
  CS_STACK_DEFAULT_CREATE_MODE
                 default creation mode: "worktree" (default) or "clone".
  CS_DEFAULT_REMOTE
                 default ssh target for -r/--remote when no host given.
                 overridden by explicit host or .codespace/remote file.
  CS_NO_INTERACTIVE
                 if set, skip interactive prompts and use defaults.
                 inferred if CURSOR_AGENT, CI, other vars are set.
                 implies CS_NO_EDIT.
  CS_NO_EDIT     if set, skip opening the new stack in an editor.
                 same effect as --no-edit.


config:
  stacks.json    lookup order at each walk-up level (first hit wins):
                   1. $CODESPACE_CONFIG_ROOT/<rel>/.codespace/stacks.json
                   2. $CODESPACE_CONFIG_ROOT/<rel>/stacks.json
                   3. <org_dir>/.codespace/stacks.json   (committed in org dir)
                   4. <org_dir>/stacks.json              (committed in org dir)
                 user-level (1-2) wins over org-committed (3-4).
                 the tool prints a note with the path used (and any ignored).
                 stack-post-create.sh is looked up next to the winning stacks.json.
                 format: { "version": "0", "stacks": { "stack-id": ["repo1", "repo2"] } }
                 repo values:
                   - repo names (siblings in org directory)
                   - clone URLs
                   - objects: { "name": "repo", "cloneURL": "url" }


sub-commands:
  create <branch> [-s stack_name] [-b base] [-r [host]] [--clone|--worktree] [--no-edit]
                  create a new stack with repos from a stack configuration.
                  "create" is implied if omitted.
                  if no stacks.json is found, creates a single worktree instead
                  (with a note) rather than failing.
                  -r/--remote: provision the stack on a remote ssh host.
                  layout mirror: $HOME/X -> remote:$HOME/codespace/X.
                  remote-bootstrap.sh (per-repo, host-level) runs before
                  each repo's post-create.

  post-create [-s stack_name]
                  run the stack post-create script in an existing stack.
                  must be run from within a stack directory (or child).
                  [-s stack_name] specifies which stack config to use (default: "default").

  extend <name>[,<name2>]...
                  extend current stack with repos from stack configs or repo names.
                  first checks stacks.json, then falls back to repos in <org> directory.
                  must be run from within an existing stack directory (or child).
                  uses the same creation mode (clone/worktree) as existing repos.

  init [<path>]   create a stacks.json configuration file in CODESPACE_CONFIG_ROOT.
				  <path> is the directory where stacks will be held.
                  if <path> is provided, uses that directory.
                  otherwise, prompts to select current or parent directory.

  ls [-g|--global] [-i|--integrated] [-S|--size] [--no-gh]
     [--older-than <duration>] [--by-commit-age] [--rm] [-q|--quiet]
                  list stacks in the current org (or all orgs with -g).
                  progress is reported on stderr for the slow modes (-i/--size);
                  rows stream as found (folder-by-folder) unless --size needs
                  to sort them.
                  filters:
                    -i, --integrated      keep only fully-integrated stacks. a
                                          repo's branch counts as integrated if
                                          it has a merged PR (looked up via gh,
                                          so squash/rebase merges are detected)
                                          or carries no commits beyond its base
                                          (tag-along repos don't block a stack).
                                          prints a per-repo breakdown (merged #N
                                          / empty / open) under each stack.
                                          falls back to a local ancestor check
                                          when gh is unavailable.
                    --no-gh               skip gh; use the local ancestor check
                                          only (offline; misses squash-merges).
                                          same as CS_NO_GH=1.
                    -S, --size            show a SIZE column (disk usage) and
                                          sort each org's stacks largest-first.
                    --older-than <dur>    keep only stacks older than <dur>.
                                          <dur> = 30d|2w|6h|45m|3600s.
                                          age = stack dir mtime by default.
                    --by-commit-age       use most recent commit timestamp across
                                          all repo branches as age, not dir mtime.
                    -g, --global          scan every org registered under
                                          $CODESPACE_CONFIG_ROOT (deduped).
                    --rm                  delete each matching stack. each repo
                                          is safety-checked (uncommitted/unpushed);
                                          if any repo is unsafe the whole stack
                                          is skipped with a warning.
                                          for force-delete use 'codespace rm -f'.
                    -q, --quiet           print only stack paths (pipe-friendly).


examples:
  codespace stack create feature1              # create stack "feature1",
                                               # add repos defined in "default" stack config in stacks.json,
                                               # checkout each repo into "feature1" branch.

  codespace stack create feature1 -s config2    # create stack from "config2" config in stacks.json.
  codespace stack create feature1 -b develop   # base the stack off of the "develop" branch,
                                               # instead of repository's default branch.
  codespace stack create feature1 --clone      # create clones, instead of worktrees.
  codespace stack create feature1 -r myhost    # provision on remote myhost (no local copy).

  codespace stack post-create            # run stack post-create script (uses "default" config)
  codespace stack post-create -s full    # run post-create using "full" stack config

  codespace stack extend be              # add repos from "be" stack config
  codespace stack extend be,infra        # add repos from "be" and "infra" stack configs
  codespace stack extend backend         # add "backend" repo directly

  codespace stack init                   # create stacks.json config file (interactive)
  codespace stack init ~/projects/myorg  # create config for stacks held in specified path

  codespace stack ls                              # list stacks in current org
  codespace stack ls --integrated                 # only stacks merged into default
  codespace stack ls --older-than 30d             # only stacks older than 30 days
  codespace stack ls --integrated --rm            # delete merged stacks (safety-checked)
  codespace stack ls -g -q | xargs -I{} echo {}   # all stacks across orgs (paths only)
```

#### sample stacks.json

```json
{
    "version": "0",
    "stacks": {
    	"default": [
            { "name": "frontend", "cloneURL": "git@github.com:kiprasmel/frontend.git" }
            { "name": "backend", "cloneURL": "git@github.com:kiprasmel/backend.git" },
    	],
        "all": [
            { "name": "admin", "cloneURL": "git@github.com:kiprasmel/admin.git" },
            { "name": "backend", "cloneURL": "git@github.com:kiprasmel/backend.git" },
            { "name": "frontend", "cloneURL": "git@github.com:kiprasmel/frontend.git" },
            { "name": "infra", "cloneURL": "git@github.com:kiprasmel/infra.git" },
            { "name": "mobile", "cloneURL": "git@github.com:kiprasmel/mobile.git" }
        ],
        "fe": [
            { "name": "frontend", "cloneURL": "git@github.com:kiprasmel/frontend.git" }
        ],
        "be": [
            { "name": "backend", "cloneURL": "git@github.com:kiprasmel/backend.git" }
        ]
    }
}
```

note: after you setup stacks, it usually becomes the default way you use codespace.
to shorten the command, you can add to your config (e.g. `.zshrc`):

```sh
export CS_DEFAULT_CREATE_TYPE="stack"
```

so instead of `codespace stack <branch>`, you can just do `codespace <branch>`,
which will try with a stack, and if none setup - will default back to a regular worktree.

## testing

bats-based test suite covering config resolution & post-create behavior.

```sh
./test/setup.sh   # one-time: vendor bats-core + helpers into test/vendor/
./test/run.sh     # run all tests; forwards args to bats
```

## misc

- working in remote codespaces: [./remote-codespaces.md](./remote-codespaces.md)
- integrating with agents: [./integrating-with-agents.md](./integrating-with-agents.md)
