# JavaScript and Electron application artifacts

For captured or bundled JavaScript that needs readable source recovery, use
`recover_javascript_sources` with an absolute `path` and absent
`output_directory`. Supply related runtime/shared/lazy files in
`additional_paths` when advertised, then analyze the returned `analysis_input`
directory together. Each input retains its own snapshot, digest and byte-range
provenance; inputs and recovered code are never executed. Recovery requires a
caller-supplied Wakaru on Linux x64; see [the recovery guide](https://github.com/morluto/rea/blob/main/docs/javascript-recovery.md).

Use `analyze_javascript_application` directly on the operator-supplied ASAR or
extracted tree. When the question concerns known source paths and the connected
schema advertises `source_paths`, select exact inventoried paths such as
`["package.json", "main.js", "preload.js"]`. Include supporting manifests or
source maps explicitly; dependencies are not implicitly analyzed. REA retains
the complete artifact inventory and identity but reads source text and analyzes
only selected files. The result and summary record `source_selection`; files
outside scope and their relationships remain unknown, so partial application
coverage does not mean the selected source failed. Use repeated `--source-path`
on either static application CLI route. Omit the selection when the question
requires complete application analysis. `detail: "summary"` reduces delivery
and does not by itself reduce analysis work.

Exact `#alias` specifiers resolve through the importer's
enclosing package `imports` map to package-local files; nested `node_modules`
packages use their own map. Wildcard, recursive, and external-package import
targets stay unresolved with that limitation. When size is unknown or large and the connected schema advertises
`detail`, request `detail: "summary"`. This returns an `inspect_analysis_view`
Evidence record with a distinct ID and a `normalized_result.parent_evidence_id`
for the complete retained application analysis. Source-map contents are part of
that static analysis. Read findings, coverage, limitations and unknowns, then
follow a specific unanswered question. Older servers without `detail` return
the complete application Evidence inline when it fits.

When the connected schema advertises `max_heap_mb` and `analysis_timeout_ms`,
these select the isolated source analyzer's old-space heap and per-source
deadline. Defaults are 1024 MiB and 300000 ms. They do not change the MCP
process heap. A Bun-hosted REA does not enforce the heap choice; on Windows it
instead limits the analyzer's committed memory to that choice plus a 512 MiB
runtime reserve.
Resource-limited analyses preserve completed static facts and
report partial semantic coverage with specific unknown scopes; this does not
mean the source is malformed. Inspect those limits before retrying a source.
When expanded relationships exceed the parent's available memory, inspect the
file's modules item view for retained `static_analysis` and
`semantic_module_analysis`. Their facts remain available even when graph links
are unknown. Cumulative result exhaustion can stop analysis before every file
is examined; the inventory and remaining unknown scopes distinguish that case.
Timeout or cancellation after source analysis begins retains partial Evidence
in the same session. A returned `error.details.partial_observation` reference
can be supplied directly to `inspect_analysis_view`. If the SDK cancels locally, retrieve its recorded ID from
the Evidence bundle before inspecting the partial analysis.

## Read a module without repeating analysis

Use the actual returned parent ID, on the same connection, as `source.evidence_id`.
The following IDs are placeholders to replace with returned values. When the
module's node ID is not already known, page identities before selecting an item.
Pages return only node IDs, paths and roles; choose a useful page size and follow
`coverage.next_offset` when another page matters:

```json
{
  "source": {
    "kind": "retained-evidence",
    "evidence_id": "ev_ACTUAL_PARENT_ID"
  },
  "view": { "kind": "page", "collection": "modules", "offset": 0, "limit": 16 }
}
```

Select the relevant page entry by its exact `node_id` and recorded role:

```json
{
  "source": {
    "kind": "retained-evidence",
    "evidence_id": "ev_ACTUAL_PARENT_ID"
  },
  "view": {
    "kind": "item",
    "collection": "modules",
    "selector": { "node_id": "jag_node_ACTUAL_NODE_ID" }
  }
}
```

Module pages include asset, bundled and source module roles, so one path can
identify several entries. Use `selector.path` only when uniqueness is established;
the returned node ID avoids needing a complete inventory to prove uniqueness. On ambiguity,
select the matching node ID from the page or the error's candidates. Follow
`next_offset` when another page matters. An item exposes that module node's
recorded observations, identity, hashes, exports and source ranges; it does not
include every child syntax observation, related edge or original source file.
An absent item fact is not evidence of absence from the whole application.

For canonical identities and retained source-range counts, use a typed reference
page instead of reading every full item:

```json
{
  "source": {
    "kind": "retained-evidence",
    "evidence_id": "ev_ACTUAL_PARENT_ID"
  },
  "view": {
    "kind": "javascript",
    "collection": "modules",
    "projection": "references",
    "where": { "path": "main.js", "kind": "javascript-module" },
    "offset": 0,
    "limit": 16
  }
}
```

Filters match exact retained strings; omit a filter to include all values, use
`path: null` for unavailable paths, and `path: ""` for a recorded empty path.
Rows preserve canonical `identity` and distinct observation support states in
`basis`. `retained_source_range_count` counts retained source-range observations,
not runtime imports or unique reference sites. Use a row's `node_id` with the item
view above for exact locations and full supporting observations. Follow
`coverage.next_offset`; page exhaustion describes matching retained rows only.
Check `source_coverage` for source selection, partial/unknown graph coverage and
unknown counts before drawing a negative conclusion.

## Trace only the remaining question

Use `trace_application_feature` on the parent application Evidence for one
literal node ID, route, string, API, IPC channel, module, or native export.
Select `incoming` for relationships leading to the seed, `outgoing` for those
leaving it, and `both` when the question needs both. Trace traversal includes
containment relationships, so even a narrow seed can expand many nodes; a
bidirectional trace can reach unrelated sibling modules. A module item or page
is preferable when its observations already answer the question. Do not treat
all reached nodes as participants in the feature.

Reuse retained parent Evidence when the server advertises it, or supply complete
Evidence inline. Include Hopper or Ghidra Evidence only when its artifact digest
matches exactly.

## Recover an oversized display

An oversized response reports `resource_constraint` and
`details.resource: "transport"`. Reuse
`details.reported_limits.evidence_reference` with `inspect_analysis_view` for a
summary, one module, or a stable page of module identities.
`export_evidence_bundle` writes the complete canonical session to a
caller-selected file. These workflows keep the original Evidence and coverage;
a broad follow-up can also exceed framing.

A client can truncate a successful result inside its text envelope without a
REA `resource_constraint`. Treat a truncation notice or incomplete JSON as a
display limitation; do not claim the full record was examined. Reuse the known
parent ID for smaller views, or export complete Evidence to a selected file
while the session remains open. If the parent ID was lost from the preview,
use the prior analysis summary or explicit ledger entries to recover it; do
not invent an ID or rerun analysis just to reproduce the same display.

BrowserWindow preferences, preload and contextBridge surfaces, IPC
registrations, utility processes, and native binding requests are static syntax
observations. Only a unique exact literal IPC channel match supports an inferred
pairing. Dynamic or ambiguous channels remain unresolved. A requested `.node`
member is not a verified native export. Never claim runtime reachability,
registration, defaults, or policy enforcement from static analysis.

For version comparison, analyze each version once, then call
`compare_application_versions`. Accept only its digest, source-map, structural
fingerprint, or non-module semantic matches. Module ordinals and minified names
are not persistent identity. Report added or removed only with complete
opposite-side coverage; otherwise report unknown.

When the question asks how one exact exported callable's returned object shape
changed, analyze each version once and then call
`compare_javascript_export_shapes` with explicit module paths and export names.
Use the returned IDs on the same connection, or complete inline Evidence
records, from both analysis calls. Accept variant
pairing only through the tool's unique exact literal discriminant. Read
`property_inventories` and each change's `presence` before treating `unknown` as
"the name was not observed": inventories list observed property names even when
values stay unknown, with a `source_range` for each paired or unpaired variant.
Array holes and mutation-invalidated slots are not observed properties.
Complete parent coverage reports presence-only
`added`/`removed` independently of unresolved values. Cite the
comparison Evidence and report JSON Pointer changes; dynamic values, ambiguous
variants, and incomplete parent-property coverage stay unknown. This is static
inference, not runtime behavior. When runtime semantics are needed, run
behavioral probes against the relevant application versions and capture them
through the available browser, Electron, or process workflows.

## Reusing application Evidence

When advertised by the connected server, application trace and compare tools
accept complete inline Evidence or
`{"kind":"retained-evidence","evidence_id":"ev_<64 lowercase hex characters>"}`
for their application input (`application`, or `left`/`right`). `inspect_analysis_view`
uses the same retained-reference form in `source`, or portable inline Evidence,
to project a summary, module page, or one module with its recorded observations.
This notation is
a template: replace it with the actual returned ID. Versions before 4.1.0 accept only full
inline Evidence. Use the exact ID
returned by the producer on the same MCP connection. Resolution does not run
analysis or select a provider; findings remain inline. Native observation
arrays still take full Evidence. `close_binary` clears retained references;
export a bundle before closing, or supply portable inline Evidence in another
connection. A missing reference includes its ID and recovery guidance.

For exact file/native metadata or processing gaps, use
`view: {kind: "javascript-facts", where: {paths: ["package.json"]}, property_keys: ["name", "operation", "analysis_status"], limit: 32}`.
Rows retain canonical node/observation identity and original Evidence. Paths
match Evidence artifact-path/source-range locations; missing properties remain
omitted and source coverage stays separate from page exhaustion. Batch paths and
select only needed property keys; complete Evidence remains accessible by export.
If names are unknown, opt into `include_available_property_keys: true`; it lists
the original keys per returned observation without unselected values. Keep each
row's node/observation identity paired when composing facts.
These rows select application-graph observations; semantic relationships and
semantic unknown records remain in the complete parent Evidence and trace tools.
