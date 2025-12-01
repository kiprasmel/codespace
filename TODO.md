# TODO

- [ ] work out the "--bare" repo setup & confirm works
- [ ] test (bats?) to confirm behavior works / avoid regressions

- [ ] "--clone" arg - clone repo instead of creating a worktree
  - benefits:
    - allows other checkouts, rebases, etc in the main repo
    - cursor more autonomous - doesn't need to ask for permission to edit files outside repo (e.g. git-rebase-todo file, which is outside worktree (in main repo))
    - better for one-off initialization, e.g. on a remote system
  - [ ] handle repo ID -- needs to find main it via remote, not via own repo name
