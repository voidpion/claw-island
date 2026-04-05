# Hooks Reference

> Source: https://code.claude.com/docs/en/hooks

Hooks are user-defined shell commands, HTTP endpoints, or LLM prompts that execute automatically at specific points in Claude Code's lifecycle. Use this reference to look up event schemas, configuration options, JSON input/output formats, and advanced features like async hooks, HTTP hooks, prompt hooks, and MCP tool hooks.

## Hook lifecycle

Hooks fire at specific points during a Claude Code session. When an event fires and a matcher matches, Claude Code passes JSON context about the event to your hook handler. For command hooks, input arrives on stdin. For HTTP hooks, it arrives as the POST request body. Your handler can then inspect the input, take action, and optionally return a decision.

| Event | When it fires |
| --- | --- |
| `SessionStart` | When a session begins or resumes |
| `UserPromptSubmit` | When you submit a prompt, before Claude processes it |
| `PreToolUse` | Before a tool call executes. Can block it |
| `PermissionRequest` | When a permission dialog appears |
| `PermissionDenied` | When a tool call is denied by the auto mode classifier |
| `PostToolUse` | After a tool call succeeds |
| `PostToolUseFailure` | After a tool call fails |
| `Notification` | When Claude Code sends a notification |
| `SubagentStart` | When a subagent is spawned |
| `SubagentStop` | When a subagent finishes |
| `TaskCreated` | When a task is being created via `TaskCreate` |
| `TaskCompleted` | When a task is being marked as completed |
| `Stop` | When Claude finishes responding |
| `StopFailure` | When the turn ends due to an API error |
| `TeammateIdle` | When an agent team teammate is about to go idle |
| `InstructionsLoaded` | When a CLAUDE.md or `.claude/rules/*.md` file is loaded into context |
| `ConfigChange` | When a configuration file changes during a session |
| `CwdChanged` | When the working directory changes |
| `FileChanged` | When a watched file changes on disk |
| `WorktreeCreate` | When a worktree is being created |
| `WorktreeRemove` | When a worktree is being removed |
| `PreCompact` | Before context compaction |
| `PostCompact` | After context compaction completes |
| `Elicitation` | When an MCP server requests user input during a tool call |
| `ElicitationResult` | After a user responds to an MCP elicitation |
| `SessionEnd` | When a session terminates |

### How a hook resolves

Example `PreToolUse` hook that blocks destructive shell commands:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "if": "Bash(rm *)",
            "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/block-rm.sh"
          }
        ]
      }
    ]
  }
}
```

The script reads the JSON input from stdin, extracts the command, and returns a `permissionDecision` of `"deny"` if it contains `rm -rf`:

```bash
#!/bin/bash
# .claude/hooks/block-rm.sh
COMMAND=$(jq -r '.tool_input.command')

if echo "$COMMAND" | grep -q 'rm -rf'; then
  jq -n '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: "Destructive command blocked by hook"
    }
  }'
else
  exit 0  # allow the command
fi
```

## Configuration

Hooks are defined in JSON settings files with three levels of nesting:

1. Choose a hook event to respond to, like `PreToolUse` or `Stop`
2. Add a matcher group to filter when it fires
3. Define one or more hook handlers to run when matched

### Hook locations

| Location | Scope | Shareable |
| --- | --- | --- |
| `~/.claude/settings.json` | All your projects | No, local to your machine |
| `.claude/settings.json` | Single project | Yes, can be committed to the repo |
| `.claude/settings.local.json` | Single project | No, gitignored |
| Managed policy settings | Organization-wide | Yes, admin-controlled |
| Plugin `hooks/hooks.json` | When plugin is enabled | Yes, bundled with the plugin |
| Skill or agent frontmatter | While the component is active | Yes, defined in the component file |

### Matcher patterns

The `matcher` field is a regex string that filters when hooks fire. Use `"*"`, `""`, or omit `matcher` entirely to match all occurrences.

| Event | What the matcher filters | Example matcher values |
| --- | --- | --- |
| `PreToolUse`, `PostToolUse`, `PostToolUseFailure`, `PermissionRequest`, `PermissionDenied` | tool name | `Bash`, `Edit\|Write`, `mcp__.*` |
| `SessionStart` | how the session started | `startup`, `resume`, `clear`, `compact` |
| `SessionEnd` | why the session ended | `clear`, `resume`, `logout`, `prompt_input_exit`, `bypass_permissions_disabled`, `other` |
| `Notification` | notification type | `permission_prompt`, `idle_prompt`, `auth_success`, `elicitation_dialog` |
| `SubagentStart` | agent type | `Bash`, `Explore`, `Plan`, or custom agent names |
| `PreCompact`, `PostCompact` | what triggered compaction | `manual`, `auto` |
| `SubagentStop` | agent type | same values as `SubagentStart` |
| `ConfigChange` | configuration source | `user_settings`, `project_settings`, `local_settings`, `policy_settings`, `skills` |
| `CwdChanged` | no matcher support | always fires on every directory change |
| `FileChanged` | filename (basename of the changed file) | `.envrc`, `.env`, any filename |
| `StopFailure` | error type | `rate_limit`, `authentication_failed`, `billing_error`, `invalid_request`, `server_error`, `max_output_tokens`, `unknown` |
| `InstructionsLoaded` | load reason | `session_start`, `nested_traversal`, `path_glob_match`, `include`, `compact` |
| `Elicitation` | MCP server name | your configured MCP server names |
| `ElicitationResult` | MCP server name | same values as `Elicitation` |
| `UserPromptSubmit`, `Stop`, `TeammateIdle`, `TaskCreated`, `TaskCompleted`, `WorktreeCreate`, `WorktreeRemove` | no matcher support | always fires on every occurrence |

For tool events, you can filter more narrowly by setting the `if` field on individual hook handlers. `if` uses permission rule syntax to match against the tool name and arguments together, so `"Bash(git *)"` runs only for `git` commands and `"Edit(*.ts)"` runs only for TypeScript files.

#### Match MCP tools

MCP tools follow the naming pattern `mcp__<server>__<tool>`:

- `mcp__memory__create_entities`: Memory server's create entities tool
- `mcp__filesystem__read_file`: Filesystem server's read file tool
- `mcp__github__search_repositories`: GitHub server's search tool

Use regex patterns: `mcp__memory__.*` matches all tools from the `memory` server, `mcp__.*__write.*` matches any tool containing "write" from any server.

### Hook handler fields

Four types of hook handlers:

- **Command hooks** (`type: "command"`): run a shell command. Input on stdin, results via exit codes and stdout.
- **HTTP hooks** (`type: "http"`): send as HTTP POST. Response body uses same JSON output format.
- **Prompt hooks** (`type: "prompt"`): send to a Claude model for single-turn evaluation.
- **Agent hooks** (`type: "agent"`): spawn a subagent with tool access to verify conditions.

#### Common fields

| Field | Required | Description |
| --- | --- | --- |
| `type` | yes | `"command"`, `"http"`, `"prompt"`, or `"agent"` |
| `if` | no | Permission rule syntax to filter when this hook runs |
| `timeout` | no | Seconds before canceling. Defaults: 600 for command, 30 for prompt, 60 for agent |
| `statusMessage` | no | Custom spinner message displayed while the hook runs |
| `once` | no | If `true`, runs only once per session then is removed. Skills only |

#### Command hook fields

| Field | Required | Description |
| --- | --- | --- |
| `command` | yes | Shell command to execute |
| `async` | no | If `true`, runs in the background without blocking |
| `shell` | no | Shell to use: `"bash"` (default) or `"powershell"` |

#### HTTP hook fields

| Field | Required | Description |
| --- | --- | --- |
| `url` | yes | URL to send the POST request to |
| `headers` | no | Additional HTTP headers as key-value pairs. Supports env var interpolation |
| `allowedEnvVars` | no | List of environment variable names that may be interpolated into header values |

#### Prompt and agent hook fields

| Field | Required | Description |
| --- | --- | --- |
| `prompt` | yes | Prompt text. Use `$ARGUMENTS` as placeholder for hook input JSON |
| `model` | no | Model to use for evaluation. Defaults to a fast model |

### Reference scripts by path

- `$CLAUDE_PROJECT_DIR`: the project root
- `${CLAUDE_PLUGIN_ROOT}`: the plugin's installation directory
- `${CLAUDE_PLUGIN_DATA}`: the plugin's persistent data directory

### Hooks in skills and agents

Hooks can be defined directly in skills and subagents using frontmatter. For subagents, `Stop` hooks are automatically converted to `SubagentStop`.

```yaml
---
name: secure-operations
description: Perform operations with security checks
hooks:
  PreToolUse:
    - matcher: "Bash"
      hooks:
        - type: command
          command: "./scripts/security-check.sh"
---
```

### Disable or remove hooks

To remove a hook, delete its entry from the settings JSON file. To temporarily disable all hooks, set `"disableAllHooks": true`.

## Hook input and output

### Common input fields

| Field | Description |
| --- | --- |
| `session_id` | Current session identifier |
| `transcript_path` | Path to conversation JSON |
| `cwd` | Current working directory when the hook is invoked |
| `permission_mode` | Current permission mode: `"default"`, `"plan"`, `"acceptEdits"`, `"auto"`, `"dontAsk"`, or `"bypassPermissions"` |
| `hook_event_name` | Name of the event that fired |

When running with `--agent` or inside a subagent:

| Field | Description |
| --- | --- |
| `agent_id` | Unique identifier for the subagent |
| `agent_type` | Agent name (e.g., `"Explore"` or `"security-reviewer"`) |

### Exit code output

- **Exit 0**: success. Claude Code parses stdout for JSON output fields.
- **Exit 2**: blocking error. Claude Code ignores stdout, feeds stderr to Claude as error message.
- **Any other exit code**: non-blocking error. stderr shown in verbose mode.

#### Exit code 2 behavior per event

| Hook event | Can block? | What happens on exit 2 |
| --- | --- | --- |
| `PreToolUse` | Yes | Blocks the tool call |
| `PermissionRequest` | Yes | Denies the permission |
| `UserPromptSubmit` | Yes | Blocks prompt processing and erases the prompt |
| `Stop` | Yes | Prevents Claude from stopping, continues the conversation |
| `SubagentStop` | Yes | Prevents the subagent from stopping |
| `TeammateIdle` | Yes | Prevents the teammate from going idle |
| `TaskCreated` | Yes | Rolls back the task creation |
| `TaskCompleted` | Yes | Prevents the task from being marked as completed |
| `ConfigChange` | Yes | Blocks the configuration change (except `policy_settings`) |
| `Elicitation` | Yes | Denies the elicitation |
| `ElicitationResult` | Yes | Blocks the response (action becomes decline) |
| `WorktreeCreate` | Yes | Any non-zero exit code causes worktree creation to fail |
| All others | No | Various non-blocking behaviors |

### JSON output

The JSON object supports three kinds of fields:

- **Universal fields** like `continue` work across all events
- **Top-level `decision` and `reason`** are used by some events to block or provide feedback
- **`hookSpecificOutput`** is a nested object for events that need richer control. Requires `hookEventName` field.

| Field | Default | Description |
| --- | --- | --- |
| `continue` | `true` | If `false`, Claude stops processing entirely |
| `stopReason` | none | Message shown to the user when `continue` is `false` |
| `suppressOutput` | `false` | If `true`, hides stdout from verbose mode output |
| `systemMessage` | none | Warning message shown to the user |

#### Decision control

| Events | Decision pattern | Key fields |
| --- | --- | --- |
| UserPromptSubmit, PostToolUse, PostToolUseFailure, Stop, SubagentStop, ConfigChange | Top-level `decision` | `decision: "block"`, `reason` |
| TeammateIdle, TaskCreated, TaskCompleted | Exit code or `continue: false` | Exit code 2 blocks. JSON `{"continue": false, "stopReason": "..."}` stops entirely |
| PreToolUse | `hookSpecificOutput` | `permissionDecision` (allow/deny/ask/defer), `permissionDecisionReason` |
| PermissionRequest | `hookSpecificOutput` | `decision.behavior` (allow/deny) |
| PermissionDenied | `hookSpecificOutput` | `retry: true` tells the model it may retry |
| WorktreeCreate | path return | Command prints path on stdout; HTTP returns `hookSpecificOutput.worktreePath` |
| Elicitation | `hookSpecificOutput` | `action` (accept/decline/cancel), `content` (form field values) |
| ElicitationResult | `hookSpecificOutput` | `action` (accept/decline/cancel), `content` (form field values override) |
| Others | None | No decision control. Used for side effects |

**Top-level decision example:**

```json
{
  "decision": "block",
  "reason": "Test suite must pass before proceeding"
}
```

**PreToolUse example:**

```json
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "allow",
    "permissionDecisionReason": "My reason here",
    "updatedInput": {
      "field_to_modify": "new value"
    },
    "additionalContext": "Current environment: production."
  }
}
```

**PermissionRequest example:**

```json
{
  "hookSpecificOutput": {
    "hookEventName": "PermissionRequest",
    "decision": {
      "behavior": "allow",
      "updatedInput": {
        "command": "npm run lint"
      }
    }
  }
}
```

## Hook events

### SessionStart

Runs when Claude Code starts a new session or resumes an existing session. Only `type: "command"` hooks are supported.

**Matcher values:** `startup`, `resume`, `clear`, `compact`

#### Input

```json
{
  "session_id": "abc123",
  "transcript_path": "/Users/.../.claude/projects/.../transcript.jsonl",
  "cwd": "/Users/...",
  "hook_event_name": "SessionStart",
  "source": "startup",
  "model": "claude-sonnet-4-6"
}
```

#### Decision control

| Field | Description |
| --- | --- |
| `additionalContext` | String added to Claude's context. Multiple hooks' values are concatenated |

#### Persist environment variables

SessionStart hooks have access to `CLAUDE_ENV_FILE` environment variable for persisting env vars:

```bash
#!/bin/bash
if [ -n "$CLAUDE_ENV_FILE" ]; then
  echo 'export NODE_ENV=production' >> "$CLAUDE_ENV_FILE"
fi
exit 0
```

### InstructionsLoaded

Fires when a `CLAUDE.md` or `.claude/rules/*.md` file is loaded into context. No decision control.

**Matcher values:** `session_start`, `nested_traversal`, `path_glob_match`, `include`, `compact`

#### Input

```json
{
  "session_id": "abc123",
  "hook_event_name": "InstructionsLoaded",
  "file_path": "/Users/my-project/CLAUDE.md",
  "memory_type": "Project",
  "load_reason": "session_start"
}
```

### UserPromptSubmit

Runs when the user submits a prompt, before Claude processes it.

#### Input

```json
{
  "session_id": "abc123",
  "hook_event_name": "UserPromptSubmit",
  "prompt": "Write a function to calculate the factorial of a number"
}
```

#### Decision control

| Field | Description |
| --- | --- |
| `decision` | `"block"` prevents the prompt from being processed |
| `reason` | Shown to the user when `decision` is `"block"` |
| `additionalContext` | String added to Claude's context |

```json
{
  "decision": "block",
  "reason": "Explanation for decision",
  "hookSpecificOutput": {
    "hookEventName": "UserPromptSubmit",
    "additionalContext": "My additional context here"
  }
}
```

### PreToolUse

Runs after Claude creates tool parameters and before processing the tool call. Matches on tool name.

#### Input

Receives `tool_name`, `tool_input`, and `tool_use_id`.

**Bash input:**

| Field | Type | Description |
| --- | --- | --- |
| `command` | string | The shell command to execute |
| `description` | string | Optional description |
| `timeout` | number | Optional timeout in milliseconds |
| `run_in_background` | boolean | Whether to run in background |

**Write input:**

| Field | Type | Description |
| --- | --- | --- |
| `file_path` | string | Absolute path to the file to write |
| `content` | string | Content to write |

**Edit input:**

| Field | Type | Description |
| --- | --- | --- |
| `file_path` | string | Absolute path to the file to edit |
| `old_string` | string | Text to find and replace |
| `new_string` | string | Replacement text |
| `replace_all` | boolean | Whether to replace all occurrences |

**Read input:** `file_path`, optional `offset`, `limit`

**Glob input:** `pattern`, optional `path`

**Grep input:** `pattern`, optional `path`, `glob`, `output_mode`, `-i`, `multiline`

**WebFetch input:** `url`, `prompt`

**WebSearch input:** `query`, optional `allowed_domains`, `blocked_domains`

**Agent input:** `prompt`, `description`, `subagent_type`, optional `model`

**AskUserQuestion input:** `questions` (array), optional `answers`

#### Decision control

| Field | Description |
| --- | --- |
| `permissionDecision` | `"allow"` skips permission prompt. `"deny"` prevents tool call. `"ask"` prompts user. `"defer"` exits gracefully for later resume |
| `permissionDecisionReason` | Reason shown to user or Claude |
| `updatedInput` | Modifies the tool's input parameters before execution |
| `additionalContext` | String added to Claude's context before the tool executes |

When multiple PreToolUse hooks return different decisions, precedence is `deny` > `defer` > `ask` > `allow`.

#### Defer a tool call for later

`"defer"` is for integrations that run `claude -p` as a subprocess. The round trip:

1. Claude calls `AskUserQuestion`. The `PreToolUse` hook fires.
2. The hook returns `permissionDecision: "defer"`. Process exits with `stop_reason: "tool_deferred"`.
3. The calling process reads `deferred_tool_use` from SDK result.
4. The calling process runs `claude -p --resume <session-id>`.
5. The hook returns `permissionDecision: "allow"` with the answer in `updatedInput`.

`"defer"` only works when Claude makes a single tool call in the turn.

### PermissionRequest

Runs when the user is shown a permission dialog. Matches on tool name.

#### Input

PermissionRequest hooks receive `tool_name` and `tool_input` fields like PreToolUse hooks, but without `tool_use_id`. An optional `permission_suggestions` array contains the "always allow" options.

```json
{
  "session_id": "abc123",
  "hook_event_name": "PermissionRequest",
  "tool_name": "Bash",
  "tool_input": {
    "command": "rm -rf node_modules",
    "description": "Remove node_modules directory"
  },
  "permission_suggestions": [
    {
      "type": "addRules",
      "rules": [{ "toolName": "Bash", "ruleContent": "rm -rf node_modules" }],
      "behavior": "allow",
      "destination": "localSettings"
    }
  ]
}
```

#### Decision control

| Field | Description |
| --- | --- |
| `behavior` | `"allow"` grants the permission, `"deny"` denies it |
| `updatedInput` | For `"allow"` only: modifies the tool's input parameters |
| `updatedPermissions` | For `"allow"` only: array of permission update entries to apply |
| `message` | For `"deny"` only: tells Claude why the permission was denied |
| `interrupt` | For `"deny"` only: if `true`, stops Claude |

```json
{
  "hookSpecificOutput": {
    "hookEventName": "PermissionRequest",
    "decision": {
      "behavior": "allow",
      "updatedInput": {
        "command": "npm run lint"
      }
    }
  }
}
```

#### Permission update entries

The `updatedPermissions` output field and the `permission_suggestions` input field both use the same array of entry objects:

| `type` | Fields | Effect |
| --- | --- | --- |
| `addRules` | `rules`, `behavior`, `destination` | Adds permission rules |
| `replaceRules` | `rules`, `behavior`, `destination` | Replaces all rules of the given `behavior` at `destination` |
| `removeRules` | `rules`, `behavior`, `destination` | Removes matching rules |
| `setMode` | `mode`, `destination` | Changes the permission mode |
| `addDirectories` | `directories`, `destination` | Adds working directories |
| `removeDirectories` | `directories`, `destination` | Removes working directories |

| `destination` | Writes to |
| --- | --- |
| `session` | in-memory only |
| `localSettings` | `.claude/settings.local.json` |
| `projectSettings` | `.claude/settings.json` |
| `userSettings` | `~/.claude/settings.json` |

A hook can echo one of the `permission_suggestions` it received as its own `updatedPermissions` output, which is equivalent to the user selecting that "always allow" option in the dialog.

### PostToolUse

Runs immediately after a tool completes successfully. Matches on tool name.

#### Input

```json
{
  "session_id": "abc123",
  "hook_event_name": "PostToolUse",
  "tool_name": "Write",
  "tool_input": { "file_path": "/path/to/file.txt", "content": "file content" },
  "tool_response": { "filePath": "/path/to/file.txt", "success": true },
  "tool_use_id": "toolu_01ABC123..."
}
```

#### Decision control

| Field | Description |
| --- | --- |
| `decision` | `"block"` prompts Claude with the `reason` |
| `reason` | Explanation shown to Claude when `decision` is `"block"` |
| `additionalContext` | Additional context for Claude |
| `updatedMCPToolOutput` | For MCP tools only: replaces the tool's output |

### PostToolUseFailure

Runs when a tool execution fails. Matches on tool name.

#### Input

Includes `error` (string) and `is_interrupt` (optional boolean).

#### Decision control

| Field | Description |
| --- | --- |
| `additionalContext` | Additional context for Claude alongside the error |

### PermissionDenied

Runs when the auto mode classifier denies a tool call. Only fires in auto mode.

#### Input

Includes `reason` field (the classifier's explanation).

#### Decision control

```json
{
  "hookSpecificOutput": {
    "hookEventName": "PermissionDenied",
    "retry": true
  }
}
```

### Notification

Runs when Claude Code sends notifications. Matches on notification type: `permission_prompt`, `idle_prompt`, `auth_success`, `elicitation_dialog`.

#### Input

```json
{
  "session_id": "abc123",
  "hook_event_name": "Notification",
  "message": "Claude needs your permission to use Bash",
  "title": "Permission needed",
  "notification_type": "permission_prompt"
}
```

Cannot block or modify notifications. Can return `additionalContext`.

### SubagentStart

Runs when a subagent is spawned via the Agent tool. Matches on agent type.

#### Input

Includes `agent_id` and `agent_type`.

Cannot block subagent creation. Can inject `additionalContext` into the subagent.

### SubagentStop

Runs when a subagent has finished responding. Matches on agent type.

#### Input

Includes `stop_hook_active`, `agent_id`, `agent_type`, `agent_transcript_path`, and `last_assistant_message`.

Uses the same decision control format as Stop hooks.

### TaskCreated

Runs when a task is being created via `TaskCreate`. No matcher support.

#### Input

Includes `task_id`, `task_subject`, optionally `task_description`, `teammate_name`, `team_name`.

#### Decision control

- **Exit code 2**: task not created, stderr fed back to model
- **JSON `{"continue": false, "stopReason": "..."}`**: stops the teammate entirely

### TaskCompleted

Runs when a task is being marked as completed. No matcher support.

Same input and decision control as TaskCreated.

### Stop

Runs when the main agent has finished responding. Does not run on user interrupt.

#### Input

Includes `stop_hook_active` (boolean) and `last_assistant_message`.

#### Decision control

| Field | Description |
| --- | --- |
| `decision` | `"block"` prevents Claude from stopping |
| `reason` | Required when `decision` is `"block"` |

### StopFailure

Runs instead of Stop when the turn ends due to an API error. Output and exit code are ignored.

#### Input

Includes `error` type (`rate_limit`, `authentication_failed`, `billing_error`, `invalid_request`, `server_error`, `max_output_tokens`, `unknown`), optional `error_details`, and `last_assistant_message`.

No decision control.

### TeammateIdle

Runs when a teammate is about to go idle. No matcher support.

#### Input

Includes `teammate_name` and `team_name`.

#### Decision control

- **Exit code 2**: teammate continues working with stderr as feedback
- **JSON `{"continue": false, "stopReason": "..."}`**: stops the teammate entirely

### ConfigChange

Runs when a configuration file changes during a session.

**Matcher values:** `user_settings`, `project_settings`, `local_settings`, `policy_settings`, `skills`

#### Input

Includes `source` and optional `file_path`.

#### Decision control

| Field | Description |
| --- | --- |
| `decision` | `"block"` prevents the change from being applied |
| `reason` | Explanation shown to the user |

`policy_settings` changes cannot be blocked.

### CwdChanged

Runs when the working directory changes. No matcher support. Only `type: "command"` hooks.

#### Input

Includes `old_cwd` and `new_cwd`.

#### Output

| Field | Description |
| --- | --- |
| `watchPaths` | Array of absolute paths. Replaces the dynamic watch list for FileChanged |

No decision control.

### FileChanged

Runs when a watched file changes on disk. The `matcher` field specifies which filenames to watch. Only `type: "command"` hooks.

#### Input

| Field | Description |
| --- | --- |
| `file_path` | Absolute path to the changed file |
| `event` | `"change"`, `"add"`, or `"unlink"` |

#### Output

| Field | Description |
| --- | --- |
| `watchPaths` | Array of absolute paths to update the dynamic watch list |

No decision control.

### WorktreeCreate

Replaces default `git worktree` behavior. Must return the absolute path to the created worktree directory.

#### Input

Includes `name` (slug identifier).

#### Output

- Command hooks: print the path on stdout
- HTTP hooks: return `{"hookSpecificOutput": {"hookEventName": "WorktreeCreate", "worktreePath": "/absolute/path"}}`

### WorktreeRemove

Fires when a worktree is being removed. No decision control.

#### Input

Includes `worktree_path`.

### PreCompact

Runs before context compaction.

**Matcher values:** `manual`, `auto`

#### Input

Includes `trigger` and `custom_instructions`.

### PostCompact

Runs after compaction completes. Same matcher values as PreCompact.

#### Input

Includes `trigger` and `compact_summary`.

No decision control.

### SessionEnd

Runs when a session ends.

**Matcher/reason values:** `clear`, `resume`, `logout`, `prompt_input_exit`, `bypass_permissions_disabled`, `other`

#### Input

Includes `reason` field.

No decision control. Default timeout: 1.5 seconds. Override with `CLAUDE_CODE_SESSIONEND_HOOKS_TIMEOUT_MS`.

### Elicitation

Runs when an MCP server requests user input mid-task. Matches on MCP server name.

#### Input

Includes `mcp_server_name`, `message`, optional `mode` (`"form"` or `"url"`), `url`, `elicitation_id`, `requested_schema`.

#### Output

| Field | Values | Description |
| --- | --- | --- |
| `action` | `accept`, `decline`, `cancel` | Whether to accept, decline, or cancel |
| `content` | object | Form field values. Only used when `action` is `accept` |

Exit code 2 denies the elicitation.

### ElicitationResult

Runs after a user responds to an MCP elicitation. Matches on MCP server name.

#### Input

Includes `mcp_server_name`, `action`, optional `mode`, `elicitation_id`, `content`.

#### Output

| Field | Values | Description |
| --- | --- | --- |
| `action` | `accept`, `decline`, `cancel` | Overrides the user's action |
| `content` | object | Overrides form field values |

Exit code 2 blocks the response (action becomes decline).

## Prompt-based hooks

Events that support all four hook types (`command`, `http`, `prompt`, `agent`):

- `PermissionRequest`, `PostToolUse`, `PostToolUseFailure`, `PreToolUse`, `Stop`, `SubagentStop`, `TaskCompleted`, `TaskCreated`, `UserPromptSubmit`

Events that support `command` and `http` only:

- `ConfigChange`, `CwdChanged`, `Elicitation`, `ElicitationResult`, `FileChanged`, `InstructionsLoaded`, `Notification`, `PermissionDenied`, `PostCompact`, `PreCompact`, `SessionEnd`, `StopFailure`, `SubagentStart`, `TeammateIdle`, `WorktreeCreate`, `WorktreeRemove`

`SessionStart` supports only `command` hooks.

### How prompt-based hooks work

1. Send the hook input and your prompt to a Claude model, Haiku by default
2. The LLM responds with structured JSON containing a decision
3. Claude Code processes the decision automatically

### Prompt hook configuration

| Field | Required | Description |
| --- | --- | --- |
| `type` | yes | Must be `"prompt"` |
| `prompt` | yes | Prompt text. Use `$ARGUMENTS` as placeholder for hook input JSON |
| `model` | no | Model to use. Defaults to a fast model |
| `timeout` | no | Timeout in seconds. Default: 30 |

### Response schema

```json
{
  "ok": true | false,
  "reason": "Explanation for the decision"
}
```

## Agent-based hooks

Agent hooks (`type: "agent"`) are like prompt hooks but with multi-turn tool access. The subagent can use Read, Grep, and Glob to investigate before returning a decision.

### Configuration

| Field | Required | Description |
| --- | --- | --- |
| `type` | yes | Must be `"agent"` |
| `prompt` | yes | Prompt describing what to verify. Use `$ARGUMENTS` |
| `model` | no | Model to use. Defaults to a fast model |
| `timeout` | no | Timeout in seconds. Default: 60 |

Same response schema as prompt hooks: `{"ok": true}` or `{"ok": false, "reason": "..."}`.

## Run hooks in the background

Set `"async": true` on a command hook to run it in the background. Async hooks cannot block or control behavior.

### Limitations

- Only `type: "command"` hooks support `async`
- Async hooks cannot block tool calls or return decisions
- Output delivered on the next conversation turn
- Each execution creates a separate background process

## Security considerations

Command hooks run with your system user's full permissions.

### Security best practices

- Validate and sanitize inputs
- Always quote shell variables: use `"$VAR"` not `$VAR`
- Block path traversal: check for `..` in file paths
- Use absolute paths for scripts
- Skip sensitive files: avoid `.env`, `.git/`, keys, etc.

## Debug hooks

Run `claude --debug` to see hook execution details. Set `CLAUDE_CODE_DEBUG_LOG_LEVEL=verbose` for more granular matching details.
