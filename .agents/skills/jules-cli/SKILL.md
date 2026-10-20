---
name: jules-cli
description: >
  Agent-first CLI for the Jules v2alpha REST API. Use this skill when
  interacting with Jules workspaces, insights, goals, assessments, tasks,
  contexts, files, or webhooks via the command line.
---

# Jules CLI — Agent Skill

## Quick Start

```bash
# Set environment (or use flags)
export JULES_API_KEY="your-key"
export JULES_BASE_URL="https://jules.googleapis.com/v2alpha"
export JULES_WORKSPACE="e09b7edc-9ec5-48e1-b8dd-c7dc8cdeb46e"

# List insights with field masking
jules insights list --fields "title,state,priority.value,severity.value"

# Get a specific workspace
jules workspaces get $JULES_WORKSPACE
```

## Invariants

1. **Always use `--fields` to control response size.** Full insights contain 7 scoring dimensions, evidence maps, and cited text — easily 2K+ tokens per item. Use field masks to stay within context window budget.
2. **Always use `--dry-run` before mutating.** Preview the exact HTTP request that will be sent. Verify the URL, method, and body before making changes.
3. **Prefer `--format ndjson` for large lists.** One JSON object per line enables streaming and line-count estimation.
4. **Environment variables take precedence.** `JULES_WORKSPACE`, `JULES_API_KEY`, `JULES_BASE_URL` are read automatically. Flags override env vars.

## Resource Recipes

### Insights (read-only)
```bash
# List all with compact output (~1K tokens for 20 items)
jules insights list --fields "title,state,priority.value,severity.value"

# Full detail on one insight
jules insights get <insight-id>

# Stream as NDJSON for processing
jules insights list --format ndjson --fields "title,priority.value"
```

### Contexts (full CRUD — primary write surface)
```bash
# Create context (structured data input)
jules contexts create --json '{"data":"...","dataSource":"zendesk","description":"Support tickets"}'

# Preview before creating
jules contexts create --json '...' --dry-run

# List contexts
jules contexts list

# Delete context
jules contexts delete <context-id>
```

### Goals
```bash
# List goals
jules goals list --fields "name,objective,autonomyLevel"

# Create goal
jules goals create --json '{"objective":"Fix login","autonomyLevel":"CREATE_ASSETS"}'

# Delete goal
jules goals delete <goal-id> --dry-run
```

### Assessments (read-only)
```bash
# List assessments (watch out: specMarkdown can be 3-6KB)
jules assessments list --fields "name,title"

# Get full assessment with PRD
jules assessments get <assessment-id>
```

### Tasks
```bash
# List tasks
jules tasks list --fields "name,title,state"

# Create task
jules tasks create --json '{"title":"Fix autosave","goals":["workspaces/.../goals/..."]}'
```

### Activities (sub-resource of tasks)
```bash
# List activity history for a task
jules activities list <task-id>

# Send message to a task
jules activities send <task-id> --json "Please also fix the undo flow"
```

### Workspaces
```bash
# Get workspace info with repos
jules workspaces get <ws-id> --fields "name,displayName,repositories"

# Add a repository
jules workspaces add-repo <ws-id> https://github.com/org/repo
```

### Webhooks
```bash
# Create webhook
jules webhooks create --json '{"url":"https://...","eventTypes":["INSIGHT_CREATED"]}'

# Verify webhook
jules webhooks verify <webhook-id>
```

## Context Window Estimates

| Command | ~Tokens (20 items) | With `--fields "title,state"` |
|---|---|---|
| `insights list` | 8,000 | ~800 |
| `goals list` | 3,000 | ~400 |
| `assessments list` | 12,000+ | ~600 |
| `contexts list` | 5,000 | ~500 |
| `tasks list` | 4,000 | ~500 |

## Guardrails

- **Never mutate without `--dry-run` first.** Always preview, then execute.
- **Use field masks aggressively.** `--fields "title,state"` reduces tokens by 90%.
- **Workspace is required for all resources except `workspaces` and `organizations`.**
- **Resource IDs are validated against path traversal, query injection, and encoding attacks.**
