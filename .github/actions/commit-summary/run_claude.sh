#!/bin/bash
set -o pipefail

# Runs Claude Code on the prepared prompt, with Workload Identity Federation first and
# CLAUDE_CODE_OAUTH_TOKEN as the fallback when federation is not set up or the run fails.
# @param $1 - Claude model

model=$1

run_claude() {
	claude -p "$(cat "$RUNNER_TEMP/commit_summary_prompt.md")" \
		--model "$model" \
		--agents "$RUNNER_TEMP/commit_summary_agents.json" \
		--permission-mode auto \
		--output-format stream-json \
		--verbose < /dev/null > "$RUNNER_TEMP/commit_summary_transcript_$1.jsonl"
}

result() {
	jq -r 'select(.type == "result") | .result' "$RUNNER_TEMP/commit_summary_transcript_$1.jsonl"
}

# Failed runs still report subtype "success", only is_error tells them apart
succeeded() {
	jq -se 'any(.[]; .type == "result" and .is_error == false)' "$RUNNER_TEMP/commit_summary_transcript_$1.jsonl" > /dev/null
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
		payload=$(cut -d. -f2 < "$ANTHROPIC_IDENTITY_TOKEN_FILE" | tr '_-' '/+')
		while (( ${#payload} % 4 )); do payload+='='; done
		base64 -d <<< "$payload" | jq -r '"Identity token sub: \(.sub)\nIdentity token job_workflow_ref: \(.job_workflow_ref)"'

		# GitHub identity tokens expire after about five minutes and each can be exchanged only once,
		# so a fresh one is written every minute for Claude Code to exchange when its access token expires
		( while sleep 60 > /dev/null 2>&1; do fetch_identity_token || echo "::warning::Could not refresh the GitHub identity token"; done ) &
		refresher=$!

		# CLAUDE_CODE_OAUTH_TOKEN takes precedence over federation credentials
		# Only the refresher needs the runner's tokens, Claude Code reads the identity token file
		if (unset CLAUDE_CODE_OAUTH_TOKEN "${!ACTIONS_@}"; run_claude wif) && succeeded wif; then
			used=wif
		else
			echo "::warning::Workload Identity Federation run failed, running again with CLAUDE_CODE_OAUTH_TOKEN: $(result wif | tail -n 1)"

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
result "$used" | tee -a "$GITHUB_STEP_SUMMARY"
