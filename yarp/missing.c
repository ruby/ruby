#include "yarp/include/yarp/missing.h"

size_t
yp_strnlen(const char *string, size_t length) {
  size_t index;
  for (index = 0; index < length && string[index] != '\0'; index++);
  return index;
}

const char *
yp_strnstr(const char *haystack, const char *needle, size_t length) {
  size_t needle_length = strnlen(needle, length);
  if (needle_length > length) return NULL;

  const char *haystack_limit = haystack + length - needle_length + 1;

  while ((haystack = memchr(haystack, needle[0], (size_t) (haystack_limit - haystack))) != NULL) {
    if (!strncmp(haystack, needle, needle_length)) return haystack;
    haystack++;
  }

  return NULL;
}

int
yp_strncasecmp(const char *string1, const char *string2, size_t length) {
  size_t offset = 0;
  int difference = 0;

  while (offset < length && string1[offset] != '\0') {
    if (string2[offset] == '\0') return string1[offset];

    unsigned char left = (unsigned char) string1[offset];
    unsigned char right = (unsigned char) string2[offset];

    if ((difference = tolower(left) - tolower(right)) != 0) return difference;
    offset++;
  }

  return difference;
}
