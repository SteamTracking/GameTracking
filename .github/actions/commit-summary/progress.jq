# Prints agent starts and finishes and every tool call from a Claude Code stream-json transcript

# First line only, as the runner also splits lines at a bare \r and parses lines starting with :: as workflow commands
def clip($n): tostring | sub("[\r\n][\\s\\S]*"; "") | gsub("[[:cntrl:]]"; " ") | if length > $n then .[:$n] + "..." else . end;
def duration: floor as $s | "\($s / 60 | floor)m\($s % 60)s";
def is_agent: .name == "Agent" or .name == "Task";

# Most telling input field of a tool call
def summary: .command // .file_path // .pattern // .path // .url // .description // .to // "" | clip(150);

# labels: agent name by spawning tool use id, kept after the agent finishes for resumed agents
# agents: start time by tool use id of each running agent
foreach (inputs | fromjson? | objects) as $event ({labels: {}, agents: {}, out: []};
	.out = []
	| if $event.type == "assistant" then
		reduce ($event.message.content[]? | select(.type == "tool_use")) as $use (.;
			# Tool calls of an agent resumed by a message may name the message as their parent
			(if $event.parent_tool_use_id == null and $use.name == "SendMessage" then
				.labels[$use.id] = "resumed \($use.input.to // "agent" | clip(100))"
			else
				.
			end)
			| if $event.parent_tool_use_id == null and ($use | is_agent) then
				.labels[$use.id] = "\($use.input.subagent_type // "agent"): \($use.input.description // "" | clip(100))"
				| .agents[$use.id] = now
				| .out += ["start \(.labels[$use.id])"]
			else
				(.labels[$event.parent_tool_use_id // ""] // "main") as $owner
				| .out += ["  [\($owner)] \($use.name) \($use.input | summary)"]
			end)
	elif $event.type == "user" then
		reduce ($event.message.content[]? | select(.type == "tool_result")) as $result (.;
			.agents[$result.tool_use_id] as $start
			| if $start == null then
				.
			else
				(if $result.is_error == true then "failed" else "done" end) as $status
				| .out += ["\($status) \(.labels[$result.tool_use_id]) after \(now - $start | duration)"]
				| del(.agents[$result.tool_use_id])
			end)
	elif $event.type == "result" then
		.out += ["finished after \(($event.duration_ms // 0) / 1000 | duration) in \($event.num_turns // "?") turns"]
	else
		.
	end;
	.out[] | "[\(now | strftime("%H:%M:%S"))] \(.)")
