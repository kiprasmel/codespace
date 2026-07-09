#!/usr/bin/env bats

# cs_parse_init_spec: pure parser mapping an --init flag value to a provisioning
# mode (auto|force|no), with a lenient comma grammar reserved for future
# sub-specs.

load helpers

setup() {
	common_setup
	source_utils
}

@test "parse_init_spec: empty value (bare --init) => force" {
	run cs_parse_init_spec ""
	assert_success
	assert_output force
}

@test "parse_init_spec: auto passes through" {
	run cs_parse_init_spec auto
	assert_success
	assert_output auto
}

@test "parse_init_spec: force passes through" {
	run cs_parse_init_spec force
	assert_success
	assert_output force
}

@test "parse_init_spec: no passes through" {
	run cs_parse_init_spec no
	assert_success
	assert_output no
}

@test "parse_init_spec: an unknown mode is a hard error" {
	run cs_parse_init_spec bogus
	assert_failure
	assert_output --partial "must be auto, force, or no"
}

@test "parse_init_spec: leading token wins; unknown sub-tokens warn + are ignored" {
	run --separate-stderr cs_parse_init_spec "force,post-create=no"
	assert_success
	assert_output force
	[[ "$stderr" == *"ignoring unsupported --init sub-option 'post-create=no'"* ]]
}
