/*
 * Parsing and printing binary64 float values.
 */
#ifndef PRISM_INTERNAL_DOUBLE_H
#define PRISM_INTERNAL_DOUBLE_H

#include "prism/buffer.h"
#include "prism/compiler/inline.h"

#include <stdbool.h>
#include <stdint.h>
#include <string.h>

/* Return the packed binary64 representation of a double. */
static PRISM_INLINE uint64_t
pm_binary64_bits(double value) {
    uint64_t bits;
    memcpy(&bits, &value, sizeof(bits));
    return bits;
}

/* Whether the sign bit is set, including for negative zero. */
bool pm_double_negative_p(double value);

/* Whether the value is finite. */
bool pm_double_finite_p(double value);

/*
 * Parse a decimal float literal into the nearest double, rounding ties to even.
 * This assumes that the format of the literal has already been validated. It
 * may start with a plus sign, which unary plus on a numeric literal leaves in
 * its token. Underscores between digits are skipped. Sets out_of_range when the
 * literal is nonzero but its value rounds to zero or to infinity.
 */
double pm_double_parse(const uint8_t *start, const uint8_t *end, bool *out_of_range);

/* Append the shortest round-tripping decimal in Ruby's Float#inspect format. */
void pm_double_string(pm_buffer_t *buffer, double value);

#endif
