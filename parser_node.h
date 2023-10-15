#ifndef RUBY_PARSER_NODE_H
#define RUBY_PARSER_NODE_H 1
/*
 * This is a header file used by only "parse.y"
 */
#include "rubyparser.h"
#include "internal/compilers.h"

#if defined(__cplusplus)
extern "C" {
#if 0
} /* satisfy cc-mode */
#endif
#endif

static inline rb_code_location_t
code_loc_gen(const rb_code_location_t *loc1, const rb_code_location_t *loc2)
{
    rb_code_location_t loc;
    loc.beg_pos = loc1->beg_pos;
    loc.end_pos = loc2->end_pos;
    return loc;
}

#if defined(__cplusplus)
#if 0
{ /* satisfy cc-mode */
#endif
}  /* extern "C" { */
#endif

#endif /* RUBY_PARSER_NODE_H */
