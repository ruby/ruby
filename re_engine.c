// Glue between Regexp (re.c) and the regexp engines: Onigmo and the Rust
// engine in regexp/. Selecting the engine and calling into Rust happen here.

#include "internal.h"
#include "internal/re.h"

#ifndef RB_DEFAULT_REGEXP_ENGINE
# define RB_DEFAULT_REGEXP_ENGINE RB_REGEXP_ENGINE_ONIGMO
#endif

#if USE_RUST_REGEXP
# include "internal/regexp_rust.h"
#endif

static rb_regexp_engine_t default_engine = RB_DEFAULT_REGEXP_ENGINE;

rb_regexp_engine_t
rb_reg_default_engine(void)
{
    return default_engine;
}

/* Returns false when +engine+ is not built into this ruby. */
bool
rb_reg_default_engine_set(rb_regexp_engine_t engine)
{
    switch (engine) {
      case RB_REGEXP_ENGINE_ONIGMO:
        break;
      case RB_REGEXP_ENGINE_RUST:
#if USE_RUST_REGEXP
        if (rb_regexp_rust_abi_version() != RB_REGEXP_RUST_ABI_VERSION) {
            rb_bug("regexp engine ABI mismatch: %u != %u",
                   rb_regexp_rust_abi_version(), RB_REGEXP_RUST_ABI_VERSION);
        }
        rb_regexp_rust_init(ONIG_ENCODING_ASCII);
        break;
#else
        return false;
#endif
      default:
        return false;
    }
    default_engine = engine;
    return true;
}
