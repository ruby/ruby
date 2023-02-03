[PATCH 1/4] YJIT: Move CodegenGlobals::freed_pages into an Rc

This allows for supplying a freed_pages vec in Rust tests. We need it so we
can test scenarios that occur after code GC.
---
 yjit/src/asm/mod.rs | 48 +++++++++++++++++++++++++++++++++------------
 yjit/src/codegen.rs | 16 ++++-----------
 2 files changed, 39 insertions(+), 25 deletions(-)

Subject: [PATCH 2/4] YJIT: other_cb is None in tests

Since the other cb is in CodegenGlobals, and we want Rust tests to be
self-contained.
---
 yjit/src/asm/mod.rs | 1 +
 1 file changed, 1 insertion(+)

Subject: [PATCH 3/4] YJIT: ARM64: Move functions out of arm64_emit()

---
 yjit/src/backend/arm64/mod.rs | 180 +++++++++++++++++-----------------
 1 file changed, 90 insertions(+), 90 deletions(-)

Subject: [PATCH 4/4] YJIT: ARM64: Fix long jumps to labels

Previously, with Code GC, YJIT panicked while trying to emit a B.cond
instruction with an offset that is not encodable in 19 bits. This only
happens when the code in an assembler instance straddles two pages.

To fix this, when we detect that a jump to a label can land on a
different page, we switch to a fresh new page and regenerate all the
code in the assembler there. We still assume that no one assembler has
so much code that it wouldn't fit inside a fresh new page.

[Bug #19385]
---
 yjit/src/backend/arm64/mod.rs | 65 ++++++++++++++++++++++++++++++++---
 1 file changed, 60 insertions(+), 5 deletions(-)
