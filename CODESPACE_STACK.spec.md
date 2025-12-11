need to implement a "stack" subcommand, first with "create" (implied):
- a "stack" is a 'codespace' of multiple repos (either worktrees or clones).
- idea is that you can create a workspace for an entire group (stack) of projects, so that e.g. agents can be initialized at the root of the stack, and work not only on a single repository, but multiple ones, this way becoming cross-functional (e.g. being able to work on both frontend and backend repos).
- configurable in CODESPACE_CONFIG_ROOT/base-path-before-repo, in stacks.json
  - should work properly - if e.g. we're in ~/my-company, and we have configurations in CODESPACE_CONFIG_ROOT/my-company/stacks.json, then use that. if we are in ~/my-company/repo, and we create a stack, and there's no configuration of stacks for that repo in CODESPACE_CONFIG_ROOT/my-company/repo/stacks.json, then should use from parent directory and check if there's a stack configured there (i.e. go up parent tree, but if goes above 1 level up, ask user to confirm before proceeding [y/n])
- "default" should be the default stack of my-company, and should be implied for `create stack [name]` if no [name] provided
- stacks.json should be an object with "version": "0", "stacks": stack[]. stack is a map of name -> repos, i.e.  { "default": ["frontend", "backend"] }
- implement in a new file codespace-stack

- stacks should be placed into ~/my-company/stack_<feature-x> with repos inside
- in the config of a stack, if the values are strings, first check if they match repository names in ~/my-company (CWD or parent CWD if inside repo, i.e. the recursive resolving). if not, then try to clone from these urls. if not possible - inform the user that: the stack configuration doesn't work - the repositories were not found locally and cannot be cloned. either a) clone the repos, or b) update the stack configuration to have clone URLs instead of repo names

- creation behavior: detect if repos are available locally, if not - clone them, and then create worktrees. unless --clone is specified, then skip that and clone from scratch. also have an environment variable CS_STACK_DEFAULT_CREATE_MODE= one of "worktree" (default) (which will do as described previously), "clone" (which will always clone, unless overridden with --worktree)

- cli signature should be `codespace stack [create] [branch-name] [-s stack-name=default]`

- codespace-stack should have its own HELP. help in codespace should be minimal to describe the base of the feature only and to tell to see codespace stack --help for more info

creation mode logic: have priorities:
- lowest priority is default inferred setting, which is worktree
- higher prio is global custom config, via CS_STACK_DEFAULT_CREATE_MODE
- highest prio is override once invoking stack cmd, either --worktree or --clone

- if there's some utilities available in codespace that are needed in codespace-stack, DO use them, instead of re-creating the same logic. if not possible without circular dependency issues, created a "utils.sh" file for this, and handle installation properly too.
- note: for handling installation, may need to have DIRNAME="$(dirname $0)" or similar handling, to make sure one script calling/importing from another works properly
