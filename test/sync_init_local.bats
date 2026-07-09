#!/usr/bin/env bats

# init-local: `codespace sync` on a remote-only codespace (a create -r stub with
# no local worktree) materializes the local worktree, SEEDS it from the remote's
# current HEAD (so remote-side commits that never hit origin are preserved), and
# converts the .codespace-remote stub into a .codespace/sync marker.

load helpers

setup() {
	common_setup
	setup_local_remote
	export CS_NO_EDIT=1
}

# Seed a bare origin with one `base` commit on master (no local base repo -- the
# codespace is remote-only). Args: name
_mk_origin() {
	local name="$1"
	git init -q --bare "$SANDBOX/$name.git"
	git clone -q "$SANDBOX/$name.git" "$SANDBOX/.seed" 2>/dev/null
	(
		cd "$SANDBOX/.seed"
		git config user.email t@e.com && git config user.name t
		echo base > f.txt
		git add -A && git commit -q -m base
		git push -q origin master
	)
	rm -rf "$SANDBOX/.seed"
}

# On the remote: clone the base, add a worktree on `feat`, and commit an extra
# change that is NOT pushed to origin. Echoes the remote worktree tip.
# Args: base_rel dest_rel
_mk_remote_only() {
	local base="$REMOTE_HOME/$1" dest="$REMOTE_HOME/$2"
	mkdir -p "$(dirname "$base")" "$(dirname "$dest")"
	HOME="$REMOTE_HOME" git clone -q "$SANDBOX/repo-a.git" "$base"
	HOME="$REMOTE_HOME" git -C "$base" worktree add -q -b feat "$dest" master >/dev/null
	echo remote-only >> "$dest/f.txt"
	HOME="$REMOTE_HOME" git -C "$dest" add -A
	HOME="$REMOTE_HOME" git -C "$dest" commit -q -m "remote-only commit"
	HOME="$REMOTE_HOME" git -C "$dest" rev-parse HEAD
}

@test "init-local (single): sync brings a remote-only stub local, seeding from the remote tip" {
	_mk_origin repo-a
	local tip
	tip="$(_mk_remote_only codespace/projects/myrepo codespace/projects/myrepo_feat)"

	# local remote-only stub: marker only, no worktree.
	local STUB="$SANDBOX/projects/myrepo_feat"
	mkdir -p "$STUB"
	cat > "$STUB/.codespace-remote" <<EOF
host=user@h
relpath=codespace/projects/myrepo_feat
kind=worktree
repo_id=projects/myrepo
branch=feat
EOF

	cd "$STUB"
	run codespace sync
	assert_success

	# materialized into a real worktree, seeded to the remote tip (remote-only
	# commit preserved locally), stub converted to a sync marker.
	assert [ -e "$STUB/.git" ]
	assert_equal "$(git -C "$STUB" rev-parse HEAD)" "$tip"
	assert_equal "$(git -C "$STUB" show -s --format=%s HEAD)" "remote-only commit"
	assert [ ! -e "$STUB/.codespace-remote" ]
	assert [ -f "$STUB/.codespace/sync" ]

	# the local base repo was cloned at $HOME/<repo_id>.
	assert [ -d "$SANDBOX/projects/myrepo/.git" ]

	# and the remote still holds that commit (nothing was reset/lost).
	assert_equal "$(remote_git codespace/projects/myrepo_feat rev-parse HEAD)" "$tip"
}

@test "init-local (single): --no-init on a remote-only stub errors instead of clobbering" {
	_mk_origin repo-a
	_mk_remote_only codespace/projects/myrepo codespace/projects/myrepo_feat >/dev/null

	local STUB="$SANDBOX/projects/myrepo_feat"
	mkdir -p "$STUB"
	cat > "$STUB/.codespace-remote" <<EOF
host=user@h
relpath=codespace/projects/myrepo_feat
kind=worktree
repo_id=projects/myrepo
branch=feat
EOF

	cd "$STUB"
	run codespace sync --no-init
	assert_failure
	assert_output --partial "remote-only codespace"
	assert [ ! -e "$STUB/.git" ]
}

@test "init-local (stack): sync brings a remote-only stack local, per repo, seeding each" {
	_mk_origin repo-a
	local tip
	tip="$(_mk_remote_only codespace/myorg/repo-a codespace/myorg/stack_feat/repo-a)"

	local STACK="$SANDBOX/myorg/stack_feat"
	mkdir -p "$STACK/repo-a"
	cat > "$STACK/repo-a/.codespace-remote" <<EOF
host=user@h
relpath=codespace/myorg/stack_feat/repo-a
kind=worktree
repo_id=myorg/repo-a
branch=feat
EOF
	cat > "$STACK/.codespace-remote" <<EOF
host=user@h
relpath=codespace/myorg/stack_feat
kind=stack
branch=feat
EOF

	cd "$STACK"
	run codespace sync
	assert_success

	assert [ -e "$STACK/repo-a/.git" ]
	assert_equal "$(git -C "$STACK/repo-a" rev-parse HEAD)" "$tip"
	assert [ ! -e "$STACK/repo-a/.codespace-remote" ]
	assert [ ! -e "$STACK/.codespace-remote" ]
	assert [ -f "$STACK/.codespace/sync" ]
	# remote-side commit survives the round-trip.
	assert_equal "$(remote_git codespace/myorg/stack_feat/repo-a rev-parse HEAD)" "$tip"
}
