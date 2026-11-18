#!/bin/bash
set -o pipefail

# Runs Claude Code on the prepared prompt, with Workload Identity Federation first and
# CLAUDE_CODE_OAUTH_TOKEN as the fallback when federation is not set up or the run fails.
# @param $1 - Claude model

model=$1

# Prints progress from the transcript stream
# Drains the rest of the stream if jq stops, so tee still writes the whole transcript
progress() {
	jq -nR --unbuffered -r -f "$GITHUB_ACTION_PATH/progress.jq"
	cat > /dev/null
}

run_claude() {
	claude -p "$(cat "$RUNNER_TEMP/commit_summary_prompt.md")" \
		--model "$model" \
		--agents "$RUNNER_TEMP/commit_summary_agents.json" \
		--permission-mode auto \
		--output-format stream-json \
		--verbose < /dev/null | tee "$RUNNER_TEMP/commit_summary_transcript_$1.jsonl" | progress
	return "${PIPESTATUS[0]}"
}

# Last non-empty result, as turns that resume after background agents each report one
result() {
	jq -nr 'last(inputs | select(.type == "result" and (.result // "") != "")) | .result // empty' "$RUNNER_TEMP/commit_summary_transcript_$1.jsonl"
}

# Failed runs still report subtype "success", only is_error tells them apart
succeeded() {
	jq -e 'select(.type == "result" and .is_error == false)' "$RUNNER_TEMP/commit_summary_transcript_$1.jsonl" > /dev/null
}

fetch_identity_token() {
	curl -fsS -H "Authorization: Bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" "$ACTIONS_ID_TOKEN_REQUEST_URL&audience=https://api.anthropic.com" \
		| jq -er .value > "$ANTHROPIC_IDENTITY_TOKEN_FILE.tmp" \
		&& mv -f "$ANTHROPIC_IDENTITY_TOKEN_FILE.tmp" "$ANTHROPIC_IDENTITY_TOKEN_FILE"
}

used=
if [[ -n "$ANTHROPIC_FEDERATION_RULE_ID" && -n "$ACTIONS_ID_TOKEN_REQUEST_URL" ]]; then
	export ANTHROPIC_IDENTITY_TOKEN_FILE="$RUNNER_TEMP/anthropic_identity_token"

	if fetch_identity_token; then
		# The claims the federation rule matches against
		jq -Rr 'split(".")[1] | gsub("-"; "+") | gsub("_"; "/") | @base64d | fromjson | "Identity token sub: \(.sub)\nIdentity token job_workflow_ref: \(.job_workflow_ref)"' "$ANTHROPIC_IDENTITY_TOKEN_FILE"

		# GitHub identity tokens expire after about five minutes and each can be exchanged only once,
		# so a fresh one is written every minute for Claude Code to exchange when its access token expires
		( while sleep 60 > /dev/null 2>&1; do fetch_identity_token || echo "::warning::Could not refresh the GitHub identity token"; done ) &
		refresher=$!

		# CLAUDE_CODE_OAUTH_TOKEN takes precedence over federation credentials
		# Only the refresher needs the runner's tokens, Claude Code reads the identity token file
		if (unset CLAUDE_CODE_OAUTH_TOKEN "${!ACTIONS_@}"; run_claude wif) && succeeded wif; then
			used=wif
		else
			# The runner also ends a line at a bare \r, which would let the result start a workflow command
			echo "::warning::Workload Identity Federation run failed, running again with CLAUDE_CODE_OAUTH_TOKEN: $(result wif | tail -n 1 | tr '\r' ' ')"

			# Notes of the failed run must not be picked up by the rerun
			rm -rf "$RUNNER_TEMP/commit_summary_notes"
			mkdir -p "$RUNNER_TEMP/commit_summary_notes"
		fi

		kill "$refresher"
	else
		echo "::warning::Could not fetch a GitHub identity token, using CLAUDE_CODE_OAUTH_TOKEN"
	fi
fi

if [[ -z "$used" ]]; then
	if [[ -z "$CLAUDE_CODE_OAUTH_TOKEN" ]]; then
		echo "::error::No usable Claude credentials"
		exit 1
	fi

	rm -f "$GITHUB_WORKSPACE/commit_summary.md"
	used=oauth
	(unset ANTHROPIC_FEDERATION_RULE_ID ANTHROPIC_ORGANIZATION_ID ANTHROPIC_SERVICE_ACCOUNT_ID ANTHROPIC_IDENTITY_TOKEN_FILE "${!ACTIONS_@}"; run_claude oauth)
fi

echo "Authenticated with: $used" >> "$GITHUB_STEP_SUMMARY"

# Disable workflow commands in the printed result
# The token is made after the result exists, so the result cannot contain it
stop_token=$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n')
echo "::stop-commands::$stop_token"
result "$used" | tee -a "$GITHUB_STEP_SUMMARY"
echo "::$stop_token::"
