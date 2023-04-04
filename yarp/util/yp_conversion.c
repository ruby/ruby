#include "yarp/util/yp_conversion.h"

uint32_t
yp_long_to_u32(long value) {
  assert(value >= 0 && value < UINT32_MAX);
  return (uint32_t) value;
}

uint32_t
yp_ulong_to_u32(unsigned long value) {
  assert(value < UINT32_MAX);
  return (uint32_t) value;
}
