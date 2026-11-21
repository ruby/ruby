/*
 * This module provides a function for parsing the values of float literals.
 */
#ifndef PRISM_INTERNAL_DOUBLE_H
#define PRISM_INTERNAL_DOUBLE_H

#include <stdbool.h>
#include <stdint.h>

/*
 * Parse a decimal float literal into the nearest double, rounding ties to even.
 * This assumes that the format of the literal has already been validated. It
 * may start with a plus sign, which unary plus on a numeric literal leaves in
 * its token. Underscores between digits are skipped. Sets out_of_range when the
 * literal is nonzero but its value rounds to zero or to infinity.
 */
double pm_double_parse(const uint8_t *start, const uint8_t *end, bool *out_of_range);

#endif
