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
codespace <branch> [-b base] [--clone [clone_url]]
codespace <sub-command>

  <branch>  can be existing (won't modify), or new (will create).

optional flags:
  -b, --base <branch>
            base branch to create from (default: remote HEAD).
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

  CS_NO_FETCH           - if set, skip fetching remote before creating worktree.
                          by default, fetches the base branch before creating.

  CS_DEFAULT_CREATE_TYPE
                        - what 'codespace create' defaults to.
                          "worktree" (default) or "stack".

  DEBUG                 - if set, prints every command executed.


.git files:
  CODESPACE_IS_CLONE    - marker file created in .git/ when using 'create' with '--clone'.


sub-commands:
  c, create   <branch> [-b base]
                                - alias for worktree or stack create.
                                  (see CS_DEFAULT_CREATE_TYPE, default: worktree)
  wt, worktree [create] <branch> [-b base] [--clone [url]]
                                - create a single-repo codespace (worktree or clone).
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
codespace stack [create] <branch> [-s stack_name] [-b base] [--clone|--worktree]
codespace stack init [<path>]
codespace stack extend <name>[,<name2>]...

  <branch>       branch name to create across all repos in the stack.
  <name>         stack config name from stacks.json, or repo name from org directory.

optional flags:
  -b, --base <branch>
                 base branch to create from (default: remote HEAD).
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
  create <branch> [-s stack_name] [-b base] [--clone|--worktree]
                  create a new stack with repos from a stack configuration.
                  "create" is implied if omitted.

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


examples:
  codespace stack create feature1              # create stack "feature1",
                                               # add repos defined in "default" stack config in stacks.json,
                                               # checkout each repo into "feature1" branch.

  codespace stack create feature1 -s config2    # create stack from "config2" config in stacks.json.
  codespace stack create feature1 -b develop   # base the stack off of the "develop" branch,
                                               # instead of repository's default branch.
  codespace stack create feature1 --clone      # create clones, instead of worktrees.

  codespace stack post-create            # run stack post-create script (uses "default" config)
  codespace stack post-create -s full    # run post-create using "full" stack config

  codespace stack extend be              # add repos from "be" stack config
  codespace stack extend be,infra        # add repos from "be" and "infra" stack configs
  codespace stack extend backend         # add "backend" repo directly

  codespace stack init                   # create stacks.json config file (interactive)
  codespace stack init ~/projects/myorg  # create config for stacks held in specified path
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

