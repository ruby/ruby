#ifndef INTERNAL_RACTOR_H                                /*-*-C-*-vi:se ft=c:*/
#define INTERNAL_RACTOR_H

#include "ruby/ractor.h"

void rb_ractor_ensure_main_ractor(const char *msg);

/* For a value read out of a class or module owned by another Ractor.  The shareable
 * constraint leaves such a value either shareable or unshareable with a shref bit
 * recorded, so the flag test is well defined.  Walking it is not: that decides an
 * unflagged object by promoting it, which only its owner may do -- and the owner does,
 * when the value is published or frozen. */
static inline bool
rb_ractor_published_shareable_p(VALUE val)
{
    return RB_SPECIAL_CONST_P(val) || RB_OBJ_SHAREABLE_P(val);
}

/* Classes and modules are shareable, so a field store publishes a shareable ->
 * unshareable edge.  A reader in another Ractor can only settle the value's shareability
 * by walking and promoting it, and promotion is the owner's job: it writes FL_SHAREABLE
 * and the owner's page bitmaps.  Do it here instead, before the store makes the value
 * visible. */
static inline void
rb_ractor_publish_shareable(VALUE val)
{
    if (!RB_SPECIAL_CONST_P(val) && !RB_OBJ_SHAREABLE_P(val) && RB_OBJ_FROZEN_RAW(val)) {
        rb_ractor_shareable_p(val);
    }
}

RUBY_SYMBOL_EXPORT_BEGIN
RUBY_SYMBOL_EXPORT_END

#endif /* INTERNAL_RACTOR_H */
