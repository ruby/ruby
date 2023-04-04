#ifndef YARP_CONVERSION_H
#define YARP_CONVERSION_H

// This file is responsible for defining functions that we use internally to
// convert between various widths safely without overflow.

#include <assert.h>
#include <stdint.h>

uint32_t
yp_long_to_u32(long value);

uint32_t
yp_ulong_to_u32(unsigned long value);

#endif
