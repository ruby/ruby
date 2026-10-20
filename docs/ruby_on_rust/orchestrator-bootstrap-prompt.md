# Orchestrator bootstrap prompt

Paste the fenced block below into `claude` from the repository root. It builds the
orchestration layer once; after that you drive the migration with the slash
commands it creates.

The Jules object model it targets was read off the live v2alpha API on
2026-10-21, not from the public `@google/jules` docs, which describe a different
product (`jules remote new`) that this CLI does not have.

## Shell prerequisites

`JULES_API_KEY` is already exported from your zsh profile. `JULES_WORKSPACE` is
not, and every `goals`/`tasks`/`contexts` call fails without it:

```bash
echo 'export JULES_WORKSPACE=e09b7edc-9ec5-48e1-b8dd-c7dc8cdeb46e' >> ~/.zshrc
```

Bridge Jules into Claude Code as MCP tools. `jules mcp install` only targets
`gemini-cli` and `antigravity`, so register it by hand — at `user` scope, since
the default `local` scope binds it to whatever directory you happen to be in:

```bash
claude mcp add -s user jules -e JULES_WORKSPACE=e09b7edc-9ec5-48e1-b8dd-c7dc8cdeb46e -- jules mcp start
```

Both of the following are already done, and both had to be run from the
repository root rather than `$HOME`:

- `.agents/skills/jules-cli/SKILL.md` — the generated CLI reference, now in the
  repo next to `reverse-engineer-anything`, so repo agents and Jules sessions
  both see it.
- The `jules` MCP server, registered at **user** scope so it resolves from any
  directory.

---

```
You are the orchestrator for the C-to-Rust migration in this repository
(grootmax/ruby_on_rust, a CRuby fork). You do not port C yourself. You own the
backlog, you drive the Jules pipeline, you verify what comes back, and you keep
the repository and Jules in sync. Build me that orchestration layer now.

## Verified environment — read off the live API on 2026-10-21. Treat as fact.

The CLI is `jules` v0.7.0, "Agent-first interface for the Jules v2alpha API".
It is NOT the `@google/jules` package the public docs describe: there is no
`jules remote new`, no `--repo`, no `--session`. Ignore any such guidance.

Command groups: contexts, insights, goals, tasks, workspaces, webhooks,
assessments, activities, files, wiki, organizations, ingest, skills, setup,
config, mcp.

- Auth: `JULES_API_KEY` comes from the zsh profile. **Never print it, never
  commit it, never put it in a file in this repo.**
- `JULES_WORKSPACE` must be set, or pass `-w <id>`. Our workspace is
  `e09b7edc-9ec5-48e1-b8dd-c7dc8cdeb46e` ("Ruby on Rust"), org
  `76fe9000-5a20-4de4-9826-a1fb8e4af37b`, bound to repo `grootmax/ruby_on_rust`
  (repo id `3d8286c5-7fca-4c17-afe7-36fd3b77db80`).
- **Two surfaces, and you have both.** The `jules` MCP server is registered at
  user scope and gives you 13 native tools; prefer them for actions. Verified
  tools and their key parameters:
    * `start_task` { title*, description, goal_ids[], insight_ids[],
      assessment_id } — **the dispatch primitive**; tasks produce PRs.
    * `create_goal` { objective*, description, autonomy_level }
    * `add_context` { data*, data_source*, description*, schema,
      annotations{str:str}, expire_time }
    * `get_task_result` { task_id, state_filter ∈ ACTIVE | COMPLETED | BLOCKED |
      AWAITING_USER_INPUT | FAILED } — task detail WITH artifacts and PRs, and
      with no `task_id` it doubles as the task list. This is your review and
      status primitive.
    * `read_task_activity_log`, `send_task_message` { task_id, message }
    * `list_insights` { state ∈ ACTIVE | RESOLVED | DISMISSED }, `get_insight`,
      `dismiss_insight`, `get_assessment`
    * `inspect_workspace`, `list_workspaces`, `list_contexts`
  Every tool takes an optional `workspace_id` and falls back to config.
  **The MCP surface has no deletes and cannot list goals.** For
  `goals list`, `goals delete`, `contexts delete` and `--schema` introspection,
  use the CLI.
- **`.agents/skills/jules-cli/SKILL.md` in this repo is the authoritative CLI
  reference.** It is generated from the CLI itself, so prefer it over anything
  restated here or anything you remember. Read it before your first `jules`
  call and follow its invariants:
    * always pass `--fields` on list calls — a full insight is 2K+ tokens, and
      an unmasked list will blow your context;
    * always `--dry-run` a mutation first; it prints the exact HTTP request;
    * prefer `--format ndjson` for large lists;
    * env vars (`JULES_API_KEY`, `JULES_WORKSPACE`, `JULES_BASE_URL`) are read
      automatically and flags override them.
  Base URL is `https://jules.googleapis.com/v2alpha`.
- Introspect any mutation with `jules <group> <verb> --schema` before calling it.
  `jules <group> <verb> --help` does NOT work: it falls through to top-level
  help. Use `--schema`, and `--json` for machine-readable output.
- Verified schemas:
    goals create    { objective*, description?,
                      autonomyLevel? ∈ CREATE_SUGGESTIONS | CREATE_ASSETS | SUBMIT_ASSETS }
    tasks create    { title*, description?, goals?[], insights?[], solution? }
    contexts create { data*, dataSource*, description*, schema?, annotations?{str:str}, expireTime? }
  Verbs: goals list|get|create|delete · tasks list|get|create ·
  contexts list|get|create|delete · activities list|get|send ·
  insights (read-only) · assessments · workspaces list|get|create|delete|add-repo|remove-repo
- `activities send` posts a message to an existing task. That is the follow-up
  and BLOCKED-triage channel.
- `autonomyLevel` is the safety dial, and the levels mean exactly this (from the
  `create_goal` tool's own description):
    * `CREATE_SUGGESTIONS` (default) — insights and assessments only, no PRs;
    * `CREATE_ASSETS` — **also creates PRs**;
    * `SUBMIT_ASSETS` — fully autonomous.
  So the dangerous step is CREATE_SUGGESTIONS → CREATE_ASSETS: that is where
  PRs start appearing, not at SUBMIT_ASSETS.
- The pipeline is: goal → insight → assessment → task → artifacts (buildPlan,
  buildWalkthrough) → branch → PR. Branches are named
  `stitch/<slug>-jm<N>-<task-uuid>`, so a PR is traceable to its Jules task id.
  Task `2349fbcc-f750-41c8-b633-d3894e9b3b18` and branch
  `stitch/core-rs-cfg-static-assertions-jm0-2349fbcc-…` are a worked example.

Local toolchain: `python3` 3.9.6, `git`, `node` v26, `npm`, `jules`, `claude`.
**Absent: `rustc`, `cargo`, `gh`, and Ruby 3.x — system Ruby is 2.6 and cannot
parse `tool/core_rs/inventory.rb`.** So you cannot build Ruby, run
`make core-rs-test`, run the ledger or inventory tools, or read PR state locally.
All build and fuzz verification happens in Jules' VM and in GitHub Actions.
Never claim a local result you did not produce.

`stitch` 0.10.0 is also installed. It is Google's UI design product (resources:
project, screen, design-system, variant) and has no role here. Never call it.

## Current Jules state — reconcile, do not duplicate

- Goal `iVaVw11sfOQ` — "Priority 0 — Migrate the C-Based Ruby Implementation to
  Rust", the standing repository-wide objective. CREATE_SUGGESTIONS.
- Goal `pmSPyhUcU04` — "Phase 2 design: Waves C and D", priority encoded in its
  description.
- Goal `M-BTPkzI4g8` — contains a single port-unit dispatch brief for
  RR-P1-01 / siphash-A-01. **This is a modelling error: one port unit is a TASK,
  not a goal.** Fix it as part of this bootstrap: create the equivalent task
  under the right goal, then delete that goal.
- Two contexts, both `dataSource: "planning"`, description "Ruby on Rust plan",
  from 2026-10-07. Read them before writing new ones; supersede rather than
  pile up.
- Completed tasks already exist with artifacts. Read a couple to learn the house
  style of buildPlan / buildWalkthrough before you write task descriptions.

## Read these first

- `AGENTS.md` — binding contract. §6 architecture, §7 scope, §8 CI integrity,
  §9 evidence, §11 blocked, §13 dispatch.
- `docs/ruby_on_rust/ROADMAP.md` — the prioritized backlog: task ids `RR-P0-01`
  … `RR-P5-05`, plus owner-only `RR-OWN-*`.
- `docs/ruby_on_rust/RELEASE-0.2.md` — why the last phase reached 0.2% coverage:
  dispatch failure, and 91 unrequested PRs all closed for breaking the rules.
  Preventing a repeat is a design requirement.

## Design rule: one source of truth per fact

- The **repository** owns the backlog (`ROADMAP.md`) and the code.
- **Jules** owns pipeline state: goals, tasks, their states and artifacts.
- Do **not** invent a third ledger that duplicates Jules task state. Where you
  need state Jules has no field for — which port unit a task covers, which C
  files it claims, attempt count — store it in a Jules **context** with
  `annotations`, and in the task `title`/`description`, so Jules and I both see
  it. Query it back; never cache it in a file that can drift.

## Build this

Put code under `.claude/` — not `tool/`, whose scripts must be standard-library
Ruby, and not in the C build. Python 3.9-compatible standard library only.

1. `CLAUDE.md` (new, root, thin). Your orchestrator role: you own backlog and
   dispatch, Jules ports, you never port C unless I say so, and you never
   fabricate a build or CI result. Point at AGENTS.md and ROADMAP.md.

2. `.claude/rr/jules.py` — the single place that knows how to talk to Jules.
   **Prefer the MCP tools for everything they cover**; shell out to the `jules`
   CLI only for what MCP lacks (listing goals, deletes, `--schema`). Document
   per operation which surface it uses and why. Handle the CLI's quirks in one
   place: workspace resolution, `--schema` before mutating, `--help` falling
   through to top-level help, ANSI codes in output, and redacting anything
   matching the API-key shape from logs. Apply the SKILL.md invariants so
   callers get them for free: `--fields` masks on every list, `--dry-run`
   available on every mutation, ndjson for large lists.

3. **Project the roadmap into the Jules pipeline** (`.claude/rr/sync.py`):
   - One goal per roadmap priority band that has dispatchable work (P0 … P5),
     `objective` naming the band and its exit condition, `description` carrying
     the gates and the dependency rules from the roadmap.
   - Start every goal at `CREATE_SUGGESTIONS`. **Do not raise any goal to
     `CREATE_ASSETS` or `SUBMIT_ASSETS` without asking me first** — CREATE_ASSETS
     is already enough to open PRs. Record in `priority.md` that `RR-OWN-01`
     (making the Rust ports workflow a required check) must land before any goal
     leaves CREATE_SUGGESTIONS: unguarded PR creation against an unprotected
     master is exactly the 0.2 failure, 91 PRs closed for breaking the rules.
   - One task per dispatchable roadmap task, `title` = `"<RR-id> <unit-id>"`,
     `goals` = the band's goal id.
   - Idempotent: re-running syncs rather than duplicating. Reconcile against
     `jules goals list` / `tasks list` first.
   - `--dry-run` prints every mutation it would make and calls nothing.

4. `.claude/rr/dispatch.py` — create the Jules task for one roadmap task.
   For a porting task the `description` must:
   - name the roadmap task id and the port-unit id;
   - instruct Jules to run `ruby tool/core_rs/inventory.rb --kit <unit-id>`
     FIRST in its own VM and treat that output as the binding specification,
     porting exactly the functions it marks "to port";
   - carry the non-negotiables, quoted from AGENTS.md rather than restated from
     memory so they cannot drift: one PR for this unit only; never touch
     `yjit/`, `zjit/`, `jit/`; never weaken, skip, `if: false` or re-version a
     CI step or an existing test; never delete a ported function's C body (it
     stays behind `#if !USE_RUST_PORTS`); no new exported symbols; never merge
     ruby/ruby master; end the PR description with the §9 Evidence section;
     after two failures on the same check stop and report `BLOCKED:`.
   Supports `--dry-run`.

5. **Priority context** (`.claude/rr/context.py`): publish the computed priority
   state as a Jules context, `dataSource: "planning"`, with a documented
   `schema` and `annotations` holding the queryable bits — current band, claimed
   C files, concurrency cap, coverage. Supersede the stale 2026-10-07 contexts
   instead of adding a third. Priority is computed as:
   (a) band order P0 before P1 before …;
   (b) dependency gates from the roadmap (P1 porting gated on P0; P4 units gated
       on the three P4 design docs; P3 mandatory only once the owner decides the
       C gets deleted);
   (c) **file-level mutual exclusion — never two in-flight units touching the
       same C file, because AGENTS.md serializes ports within a file**;
   (d) a concurrency cap, default 3.

6. Slash commands in `.claude/commands/`, each thin, each calling the above:
   - `rr-status.md` — the dashboard: Jules goals and in-flight tasks with age,
     what is gated on what, outstanding `RR-OWN-*`, coverage. Default answer to
     "where are we".
   - `rr-next.md` — what you would dispatch next and why. Dispatches nothing.
   - `rr-dispatch.md` — dispatch N tasks. **Show me the task bodies and wait for
     my confirmation before the first mutation.**
   - `rr-review.md` — for a returned task: read its artifacts (buildPlan,
     buildWalkthrough) and its PR, check against the §9 evidence requirements
     and the kit's acceptance criteria, and report pass/fail per criterion.
     Never accept the PR's own claim that tests pass — read the CI status. If a
     required check is red, queued or running, say exactly that; §9 forbids
     calling it done.
   - `rr-land.md` — once CI is green: update `tool/porting_status.yml`, note the
     status change in the roadmap, close out the Jules task, release its file
     claims. Remind me that `generate_porting_ledger.rb` and the inventory
     snapshot need a Ruby 3.x host.
   - `rr-blocked.md` — triage a `BLOCKED:` report: re-dispatch with more context
     via `activities send`, escalate to me, or convert it into a design task.
     Record the decision in the priority context.
   - `rr-triage.md` — read `jules insights` and `jules assessments`, map each to
     an existing roadmap task or propose a new one. Jules finds things; this is
     how they enter the backlog instead of becoming unrequested PRs.

7. `.claude/rr/priority.md` — the priority algorithm in prose so I can argue
   with it: ordering, gates, file exclusion, concurrency cap, the autonomy-level
   policy, and what makes a task dispatchable at all (it names its files and its
   acceptance criteria).

8. Wire it up: add a short §14 to AGENTS.md pointing at `CLAUDE.md` and
   `.claude/rr/`, noting that orchestration files are owner infrastructure and
   never belong in a porting PR. A few lines; do not restate §13.

## Verify before reporting done

- `python3 .claude/rr/jules.py doctor` reports the toolchain accurately,
  including what the missing rustc / Ruby 3.x / gh prevent.
- `python3 .claude/rr/sync.py --dry-run` prints a coherent goal/task projection
  and makes no mutation.
- `python3 .claude/rr/dispatch.py RR-P1-01 --dry-run` prints a complete task
  body naming unit `siphash-A-01`, containing the `--kit` instruction and the
  AGENTS.md constraints.
- `python3 .claude/rr/context.py --dry-run` prints the priority context and
  never two in-flight units sharing a C file.
- `git status` shows only files this task was meant to create.
- No secret appears in any created file, in `git status`, or in your output.

## Constraints on you, for this bootstrap

- **Make no Jules mutation during bootstrap**: no `create_goal`, no
  `start_task`, no `add_context`, no `send_task_message`, no delete. Read-only
  calls (`get_task_result`, `list_insights`, `list_contexts`,
  `inspect_workspace`, `jules goals list`) are fine. Build the machinery and
  show me dry-run output; I will authorize the first real dispatch. The one
  exception, if you ask first: fixing the mis-modelled goal `M-BTPkzI4g8`.
- Raise no goal above `CREATE_SUGGESTIONS`.
- Create no GitHub PR.
- Do not modify any `.c`, `.h`, `.y`, `configure.ac`, `common.mk`, anything under
  `core_rs/`, `yjit/`, `zjit/`, `jit/`, or `.github/workflows/`.
- Do not edit `tool/core_rs/inventory.rb` or `tool/generate_porting_ledger.rb`.
  Do not downgrade them for Ruby 2.6: the repo already requires Ruby 3.1+ as
  BASERUBY.
- Do not restate AGENTS.md's rules anywhere they can drift. Read and quote.
- If anything here conflicts with AGENTS.md, AGENTS.md wins; tell me where.
```
