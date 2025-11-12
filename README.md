# codespace

git worktrees, with convenience.

## features

- post-create scripts
  - install dependencies, link files, etc
- simple setup for storing files outside main repository (e.g. AGENTS.md with your preferences)
  - while still tracking in git, just in a separate repo

## use-cases

- working on multiple features at the same time
- reviewing PRs locally
- running multiple agents in parallel on the same task, comparing output, picking best results
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
git config --global alias.cs = codespace
```

## usage

```console
$ codespace -h

Usage:
codespace <branch> [base]

  <branch>  can be existing (won't modify), or new (will create).
  [base]    is where the <branch> will point to (if creating a new one).
            [base] defaults to symbolic-ref of remote HEAD.


env vars:
  GUI_EDITOR or EDITOR  - for opening a newly created codespace in an editor.

  CODESPACE_CONFIG_ROOT - dir where configs for codespaces are placed.
                          used to configure post-create scripts, link hidden files, etc.
                          layout of the dir should be: "/org/repo/" (see also base-repo).
                          inside:
					        - files, scripts, etc that are not in the repo itself.
                            - ".codespace/post-create" script - ran on codespace creation.

  DEBUG                 - if set, prints every command executed.


sub-commands:
  c, create    <branch> [base]  - same as no sub-command (see above).
  post-create  [cs_path]        - run the post-create script for a given codespace.
                                  [cs_path] defaults to codespace inside cwd.
  repo-id      [rel_to]         - get the repo ID to locate appropriate config location
                                  in "$CODESPACE_CONFIG_ROOT".
								  assumes that repositories are placed in "$HOME/org/repo"
								  (controllable via [rel_to], which defaults to "$HOME").
                                  extracts "/org/repo" portion of "$PWD" wrt [rel_to].
  base-repo                     - absolute path to the root of the base repository.
  cleanpath    <string>         - sanitize path for worktree dir (replace /, :, spaces etc)
```
