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
git config --global alias.css "\!codespace stack"
```

## usage

### codespace

```console
$ codespace -h

Usage:
codespace <branch> [base]
codespace <branch> [base] [--clone [clone_url]]
codespace <sub-command>

  <branch>  can be existing (won't modify), or new (will create).
  [base]    is where the <branch> will point to (if creating a new one).
            [base] defaults to symbolic-ref of remote HEAD.

optional flags:
  --clone [clone_url]
            create a standalone clone instead of a worktree.
            benefits: allows other checkouts/rebases in main repo,
            better for one-off initialization on remote systems.
            [clone_url] - inferred from remote if inside a git repo.


env vars:
  GUI_EDITOR or EDITOR  - for opening a newly created codespace in an editor.

  CODESPACE_CONFIG_ROOT - dir where configs for codespaces are placed.
                          used to configure post-create scripts, link hidden files, etc.
                          layout of the dir should be: "/org/repo/" (see also base-repo).
                          inside:
                            - files, scripts, etc that are not in the repo itself.
                            - ".codespace/post-create" script - ran on codespace creation.

  CS_NO_INTERACTIVE     - if set, skip interactive prompts and use defaults.
                          inferred if CURSOR_AGENT or CI is set.

  DEBUG                 - if set, prints every command executed.


.git files:
  CODESPACE_IS_CLONE    - marker file created in .git/ when using 'create' with '--clone'.


sub-commands:
  c, create   <branch> [base]   - same as no sub-command (see above).
  s, stack    [create] <branch> - create a multi-repo codespace (stack).
                                  see 'codespace stack --help' for details.
  post-create [cs_path]         - run the post-create script for a given codespace.
                                  [cs_path] defaults to codespace inside cwd.
  rm, remove  <branch|path>     - remove a codespace (worktree or clone).
                                  checks for uncommitted/unpushed changes before removing.
                                  [-f, --force] - ignore safety checks.
  find        <branch>          - find codespace/stack path by branch name.
  edit        <branch>          - find codespace/stack and open in editor.
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
codespace stack [create] <branch> [-s stack_name] [--clone|--worktree]
codespace stack init
codespace stack extend <name>[,<name2>]...

  <branch>       branch name to create across all repos in the stack.
  <name>         stack config name from stacks.json, or repo name from org directory.

optional flags:
  -s, --stack <stack_name>
                 stack config name from stacks.json (default: "default").
  --clone        force clone mode (fresh clones for all repos).
  --worktree     force worktree mode (create worktrees from local repos).


env vars:
  CS_STACK_DEFAULT_CREATE_MODE
                 default creation mode: "worktree" (default) or "clone".
  CS_NO_INTERACTIVE
                 if set, skip interactive prompts and use defaults.
                 inferred if CURSOR_AGENT, CI, other vars are set.


config:
  stacks.json    located in $CODESPACE_CONFIG_ROOT/<org>/stacks.json
                 format: { "version": "0", "stacks": { "stack-id": ["repo1", "repo2"] } }
                 repo values:
                   - repo names (siblings in org directory)
                   - clone URLs
                   - objects: { "name": "repo", "cloneURL": "url" }


sub-commands:
  create <branch> [-s stack_name] [--clone|--worktree]
                  create a new stack with repos from a stack configuration.
                  "create" is implied if omitted.

  init            create a stacks.json configuration file.

  extend <name>[,<name2>]...
                  extend current stack with repos from stack configs or repo names.
                  first checks stacks.json, then falls back to repos in <org> directory.
                  must be run from within an existing stack directory (or child).
                  uses the same creation mode (clone/worktree) as existing repos.


examples:
  codespace stack init                   # create stacks.json config file
  codespace stack        feature-x       # create "default" stack, branches "feature-x" in all repos
  codespace stack create feature-x       # same as above
  codespace stack feature-x -s full      # create stack from "full" config in stacks.json
  codespace stack feature-x --clone      # create clones, instead of worktrees
  codespace stack extend be              # add repos from "be" stack config
  codespace stack extend be,infra        # add repos from "be" and "infra" stack configs
  codespace stack extend backend         # add "backend" repo directly
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

