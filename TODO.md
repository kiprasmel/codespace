# TODO

## done

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
- [ ] test (bats?) to confirm behavior works / avoid regressions

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

- [ ] alias "open" to "edit"

- [ ] rename "stack_name" to "stack_config", to avoid confusion between an actual stack where repos are held, vs the stack config name inside stacks.json
  - [ ] -s flag too?

- [ ] stack-post-create should probably run everything that's done after a stack is created, instead of just the stack-post-create.sh script
  - post-create scripts of each repo
  - stack-post-create.sh script
  - other setup logic etc, basically everything that's done after creation (hence, "post-create")
  - idk if needs differentiation from the "just the script" case
