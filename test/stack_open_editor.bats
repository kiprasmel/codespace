#!/usr/bin/env bats

# cs_stack_create_open_editor — remote stack create opens editor with an
# absolute remote path (not a literal $HOME).

load helpers

setup() {
	common_setup
	source_stack
	install_ssh_shims

	EDITOR_BIN="$BATS_TEST_TMPDIR/editor-bin"
	EDITOR_LOG="$BATS_TEST_TMPDIR/editor.log"
	mkdir -p "$EDITOR_BIN"
	: > "$EDITOR_LOG"
	cat > "$EDITOR_BIN/cursor" <<'ED'
#!/usr/bin/env bash
{ printf 'cursor'; for a in "$@"; do printf ' %s' "$a"; done; printf '\n'; } >> "$EDITOR_LOG"
ED
	chmod +x "$EDITOR_BIN/cursor"
	export PATH="$EDITOR_BIN:$PATH"
	export GUI_EDITOR=cursor EDITOR=cursor EDITOR_LOG
}

@test "stack_create_open_editor: remote passes resolved absolute path, not literal \$HOME" {
	unset CS_NO_EDIT
	export SSH_NEXT_STDOUT="/home/remoteuser"
	remote_host="myhost"
	stack_dest_rel="codespace/projects/stack_feat"

	cs_stack_create_open_editor
	wait

	grep -qF -- "--remote ssh-remote+myhost /home/remoteuser/codespace/projects/stack_feat" "$EDITOR_LOG"
	refute grep -qF -- '$HOME' "$EDITOR_LOG"
}
