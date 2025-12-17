# TODO

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
