#include "yarp/include/yarp/unescape.h"

/******************************************************************************/
/* Character checks                                                           */
/******************************************************************************/

static inline bool
yp_char_is_hexadecimal_digits(const char *c, size_t length) {
  for (size_t index = 0; index < length; index++) {
    if (!yp_char_is_hexadecimal_digit(c[index])) {
      return false;
    }
  }
  return true;
}

/******************************************************************************/
/* Lookup tables for characters                                               */
/******************************************************************************/

// This is a lookup table for unescapes that only take up a single character.
static const unsigned char unescape_chars[] = {
  ['\''] = '\'',
  ['\\'] = '\\',
  ['a'] = '\a',
  ['b'] = '\b',
  ['e'] = '\033',
  ['f'] = '\f',
  ['n'] = '\n',
  ['r'] = '\r',
  ['s'] = ' ',
  ['t'] = '\t',
  ['v'] = '\v'
};

// This is a lookup table for whether or not an ASCII character is printable.
static const bool ascii_printable_chars[] = {
  0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
  1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
  1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
  1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 1, 1, 1,
  1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
  1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0
};

static inline bool
char_is_ascii_printable(const char c) {
  return ascii_printable_chars[(unsigned char) c];
}

/******************************************************************************/
/* Unescaping for segments                                                    */
/******************************************************************************/

// Scan the 1-3 digits of octal into the value. Returns the number of digits
// scanned.
static inline size_t
unescape_octal(const char *backslash, unsigned char *value) {
  *value = (unsigned char) (backslash[1] - '0');
  if (!yp_char_is_octal_digit(backslash[2])) {
    return 2;
  }

  *value = (*value << 3) | (backslash[2] - '0');
  if (!yp_char_is_octal_digit(backslash[3])) {
    return 3;
  }

  *value = (*value << 3) | (backslash[3] - '0');
  return 4;
}

// Convert a hexadecimal digit into its equivalent value.
static inline unsigned char
unescape_hexadecimal_digit(const char value) {
  return (value <= '9') ? (unsigned char) (value - '0') : (value & 0x7) + 9;
}

// Scan the 1-2 digits of hexadecimal into the value. Returns the number of
// digits scanned.
static inline size_t
unescape_hexadecimal(const char *backslash, unsigned char *value) {
  *value = unescape_hexadecimal_digit(backslash[2]);
  if (!yp_char_is_hexadecimal_digit(backslash[3])) {
    return 3;
  }

  *value = (*value << 4) | unescape_hexadecimal_digit(backslash[3]);
  return 4;
}

// Scan the 4 digits of a Unicode escape into the value. Returns the number of
// digits scanned. This function assumes that the characters have already been
// validated.
static inline void
unescape_unicode(const char *string, size_t length, uint32_t *value) {
  *value = 0;
  for (size_t index = 0; index < length; index++) {
    if (index != 0) *value <<= 4;
    *value |= unescape_hexadecimal_digit(string[index]);
  }
}

// Accepts the pointer to the string to write the unicode value along with the
// 32-bit value to write. Writes the UTF-8 representation of the value to the
// string and returns the number of bytes written.
static inline size_t
unescape_unicode_write(char *dest, uint32_t value, const char *start, const char *end, yp_list_t *error_list) {
  unsigned char *bytes = (unsigned char *) dest;

  if (value <= 0x7F) {
    // 0xxxxxxx
    bytes[0] = value;
    return 1;
  }

  if (value <= 0x7FF) {
    // 110xxxxx 10xxxxxx
    bytes[0] = 0xC0 | (value >> 6);
    bytes[1] = 0x80 | (value & 0x3F);
    return 2;
  }

  if (value <= 0xFFFF) {
    // 1110xxxx 10xxxxxx 10xxxxxx
    bytes[0] = 0xE0 | (value >> 12);
    bytes[1] = 0x80 | ((value >> 6) & 0x3F);
    bytes[2] = 0x80 | (value & 0x3F);
    return 3;
  }

  // At this point it must be a 4 digit UTF-8 representation. If it's not, then
  // the input is invalid.
  if (value <= 0x10FFFF) {
    // 11110xxx 10xxxxxx 10xxxxxx 10xxxxxx
    bytes[0] = 0xF0 | (value >> 18);
    bytes[1] = 0x80 | ((value >> 12) & 0x3F);
    bytes[2] = 0x80 | ((value >> 6) & 0x3F);
    bytes[3] = 0x80 | (value & 0x3F);
    return 4;
  }

  // If we get here, then the value is too big. This is an error, but we don't
  // want to just crash, so instead we'll add an error to the error list and put
  // in a replacement character instead.
  yp_diagnostic_list_append(error_list, start, end, "Invalid Unicode escape sequence.");
  bytes[0] = 0xEF;
  bytes[1] = 0xBF;
  bytes[2] = 0xBD;
  return 3;
}

typedef enum {
  YP_UNESCAPE_FLAG_NONE = 0,
  YP_UNESCAPE_FLAG_CONTROL = 1,
  YP_UNESCAPE_FLAG_META = 2,
  YP_UNESCAPE_FLAG_EXPECT_SINGLE = 4
} yp_unescape_flag_t;

// Unescape a single character value based on the given flags.
static inline unsigned char
unescape_char(const unsigned char value, const unsigned char flags) {
  unsigned char unescaped = value;

  if (flags & YP_UNESCAPE_FLAG_CONTROL) {
    unescaped &= 0x1f;
  }

  if (flags & YP_UNESCAPE_FLAG_META) {
    unescaped |= 0x80;
  }

  return unescaped;
}

// Read a specific escape sequence into the given destination.
static const char *
unescape(char *dest, size_t *dest_length, const char *backslash, const char *end, yp_list_t *error_list, const unsigned char flags, bool write_to_str) {
  switch (backslash[1]) {
    // \a \b \e \f \n \r \s \t \v
    case 'a':
    case 'b':
    case 'e':
    case 'f':
    case 'n':
    case 'r':
    case 's':
    case 't':
    case 'v':
      if (write_to_str) {
        dest[(*dest_length)++] = (char) unescape_char(unescape_chars[(unsigned char) backslash[1]], flags);
      }
      return backslash + 2;
    // \nnn         octal bit pattern, where nnn is 1-3 octal digits ([0-7])
    case '0': case '1': case '2': case '3': case '4':
    case '5': case '6': case '7': case '8': case '9': {
      unsigned char value;
      const char *cursor = backslash + unescape_octal(backslash, &value);

      if (write_to_str) {
        dest[(*dest_length)++] = (char) unescape_char(value, flags);
      }
      return cursor;
    }
    // \xnn         hexadecimal bit pattern, where nn is 1-2 hexadecimal digits ([0-9a-fA-F])
    case 'x': {
      unsigned char value;
      const char *cursor = backslash + unescape_hexadecimal(backslash, &value);

      if (write_to_str) {
        dest[(*dest_length)++] = (char) unescape_char(value, flags);
      }
      return cursor;
    }
    // \u{nnnn ...} Unicode character(s), where each nnnn is 1-6 hexadecimal digits ([0-9a-fA-F])
    // \unnnn       Unicode character, where nnnn is exactly 4 hexadecimal digits ([0-9a-fA-F])
    case 'u': {
      if ((flags & YP_UNESCAPE_FLAG_CONTROL) | (flags & YP_UNESCAPE_FLAG_META)) {
        yp_diagnostic_list_append(error_list, backslash, backslash + 2, "Unicode escape sequence cannot be used with control or meta flags.");
        return backslash + 2;
      }

      if ((backslash + 3) < end && backslash[2] == '{') {
        const char *unicode_cursor = backslash + 3;
        const char *extra_codepoints_start;
        int codepoints_count = 0;

        unicode_cursor += yp_strspn_whitespace(unicode_cursor, end - unicode_cursor);

        while ((*unicode_cursor != '}') && (unicode_cursor < end)) {
          const char *unicode_start = unicode_cursor;
          size_t hexadecimal_length = yp_strspn_hexadecimal_digit(unicode_cursor, end - unicode_cursor);

          // \u{nnnn} character literal allows only 1-6 hexadecimal digits
          if (hexadecimal_length > 6)
            yp_diagnostic_list_append(error_list, unicode_cursor, unicode_cursor + hexadecimal_length, "invalid Unicode escape.");

          // there are not hexadecimal characters
          if (hexadecimal_length == 0) {
            yp_diagnostic_list_append(error_list, unicode_cursor, unicode_cursor + hexadecimal_length, "unterminated Unicode escape");
            return unicode_cursor;
          }

          unicode_cursor += hexadecimal_length;

          codepoints_count++;
          if (flags & YP_UNESCAPE_FLAG_EXPECT_SINGLE && codepoints_count == 2)
            extra_codepoints_start = unicode_start;

          uint32_t value;
          unescape_unicode(unicode_start, (size_t) (unicode_cursor - unicode_start), &value);
          if (write_to_str) {
            *dest_length += unescape_unicode_write(dest + *dest_length, value, unicode_start, unicode_cursor, error_list);
          }

          unicode_cursor += yp_strspn_whitespace(unicode_cursor, end - unicode_cursor);
        }

        // ?\u{nnnn} character literal should contain only one codepoint and cannot be like ?\u{nnnn mmmm}
        if (flags & YP_UNESCAPE_FLAG_EXPECT_SINGLE && codepoints_count > 1)
          yp_diagnostic_list_append(error_list, extra_codepoints_start, unicode_cursor - 1, "Multiple codepoints at single character literal");

        return unicode_cursor + 1;
      }

      if ((backslash + 2) < end && yp_char_is_hexadecimal_digits(backslash + 2, 4)) {
        uint32_t value;
        unescape_unicode(backslash + 2, 4, &value);

        if (write_to_str) {
          *dest_length += unescape_unicode_write(dest + *dest_length, value, backslash + 2, backslash + 6, error_list);
        }
        return backslash + 6;
      }

      yp_diagnostic_list_append(error_list, backslash, backslash + 2, "Invalid Unicode escape sequence");
      return backslash + 2;
    }
    // \c\M-x       meta control character, where x is an ASCII printable character
    // \c?          delete, ASCII 7Fh (DEL)
    // \cx          control character, where x is an ASCII printable character
    case 'c':
      if (backslash + 2 >= end) {
        yp_diagnostic_list_append(error_list, backslash, backslash + 1, "Invalid control escape sequence");
        return end;
      }

      if (flags & YP_UNESCAPE_FLAG_CONTROL) {
        yp_diagnostic_list_append(error_list, backslash, backslash + 1, "Control escape sequence cannot be doubled.");
        return backslash + 2;
      }

      switch (backslash[2]) {
        case '\\':
          return unescape(dest, dest_length, backslash + 2, end, error_list, flags | YP_UNESCAPE_FLAG_CONTROL, write_to_str);
        case '?':
          if (write_to_str) {
            dest[(*dest_length)++] = (char) unescape_char(0x7f, flags);
          }
          return backslash + 3;
        default: {
          if (!char_is_ascii_printable(backslash[2])) {
            yp_diagnostic_list_append(error_list, backslash, backslash + 1, "Invalid control escape sequence");
            return backslash + 2;
          }

          if (write_to_str) {
            dest[(*dest_length)++] = (char) unescape_char((const unsigned char) backslash[2], flags | YP_UNESCAPE_FLAG_CONTROL);
          }
          return backslash + 3;
        }
      }
    // \C-x         control character, where x is an ASCII printable character
    // \C-?         delete, ASCII 7Fh (DEL)
    case 'C':
      if (backslash + 3 >= end) {
        yp_diagnostic_list_append(error_list, backslash, backslash + 1, "Invalid control escape sequence");
        return end;
      }

      if (flags & YP_UNESCAPE_FLAG_CONTROL) {
        yp_diagnostic_list_append(error_list, backslash, backslash + 1, "Control escape sequence cannot be doubled.");
        return backslash + 2;
      }

      if (backslash[2] != '-') {
        yp_diagnostic_list_append(error_list, backslash, backslash + 1, "Invalid control escape sequence");
        return backslash + 2;
      }

      switch (backslash[3]) {
        case '\\':
          return unescape(dest, dest_length, backslash + 3, end, error_list, flags | YP_UNESCAPE_FLAG_CONTROL, write_to_str);
        case '?':
          if (write_to_str) {
            dest[(*dest_length)++] = (char) unescape_char(0x7f, flags);
          }
          return backslash + 4;
        default:
          if (!char_is_ascii_printable(backslash[3])) {
            yp_diagnostic_list_append(error_list, backslash, backslash + 2, "Invalid control escape sequence");
            return backslash + 2;
          }

          if (write_to_str) {
            dest[(*dest_length)++] = (char) unescape_char((const unsigned char) backslash[3], flags | YP_UNESCAPE_FLAG_CONTROL);
          }
          return backslash + 4;
      }
    // \M-\C-x      meta control character, where x is an ASCII printable character
    // \M-\cx       meta control character, where x is an ASCII printable character
    // \M-x         meta character, where x is an ASCII printable character
    case 'M': {
      if (backslash + 3 >= end) {
        yp_diagnostic_list_append(error_list, backslash, backslash + 1, "Invalid control escape sequence");
        return end;
      }

      if (flags & YP_UNESCAPE_FLAG_META) {
        yp_diagnostic_list_append(error_list, backslash, backslash + 2, "Meta escape sequence cannot be doubled.");
        return backslash + 2;
      }

      if (backslash[2] != '-') {
        yp_diagnostic_list_append(error_list, backslash, backslash + 2, "Invalid meta escape sequence");
        return backslash + 2;
      }

      if (backslash[3] == '\\') {
        return unescape(dest, dest_length, backslash + 3, end, error_list, flags | YP_UNESCAPE_FLAG_META, write_to_str);
      }

      if (char_is_ascii_printable(backslash[3])) {
        if (write_to_str) {
          dest[(*dest_length)++] = (char) unescape_char((const unsigned char) backslash[3], flags | YP_UNESCAPE_FLAG_META);
        }
        return backslash + 4;
      }

      yp_diagnostic_list_append(error_list, backslash, backslash + 2, "Invalid meta escape sequence");
      return backslash + 3;
    }
    // In this case we're escaping something that doesn't need escaping.
    default:
      {
        if (write_to_str) {
          dest[(*dest_length)++] = backslash[1];
        }
        return backslash + 2;
      }
  }
}

/******************************************************************************/
/* Public functions and entrypoints                                           */
/******************************************************************************/

// Unescape the contents of the given token into the given string using the
// given unescape mode. The supported escapes are:
//
// \a             bell, ASCII 07h (BEL)
// \b             backspace, ASCII 08h (BS)
// \t             horizontal tab, ASCII 09h (TAB)
// \n             newline (line feed), ASCII 0Ah (LF)
// \v             vertical tab, ASCII 0Bh (VT)
// \f             form feed, ASCII 0Ch (FF)
// \r             carriage return, ASCII 0Dh (CR)
// \e             escape, ASCII 1Bh (ESC)
// \s             space, ASCII 20h (SPC)
// \\             backslash
// \nnn           octal bit pattern, where nnn is 1-3 octal digits ([0-7])
// \xnn           hexadecimal bit pattern, where nn is 1-2 hexadecimal digits ([0-9a-fA-F])
// \unnnn         Unicode character, where nnnn is exactly 4 hexadecimal digits ([0-9a-fA-F])
// \u{nnnn ...}   Unicode character(s), where each nnnn is 1-6 hexadecimal digits ([0-9a-fA-F])
// \cx or \C-x    control character, where x is an ASCII printable character
// \M-x           meta character, where x is an ASCII printable character
// \M-\C-x        meta control character, where x is an ASCII printable character
// \M-\cx         same as above
// \c\M-x         same as above
// \c? or \C-?    delete, ASCII 7Fh (DEL)
//
__attribute__((__visibility__("default"))) extern void
yp_unescape_manipulate_string(const char *value, size_t length, yp_string_t *string, yp_unescape_type_t unescape_type, yp_list_t *error_list) {
  if (unescape_type == YP_UNESCAPE_NONE) {
    // If we're not unescaping then we can reference the source directly.
    yp_string_shared_init(string, value, value + length);
    return;
  }

  const char *backslash = memchr(value, '\\', length);

  if (backslash == NULL) {
    // Here there are no escapes, so we can reference the source directly.
    yp_string_shared_init(string, value, value + length);
    return;
  }

  // Here we have found an escape character, so we need to handle all escapes
  // within the string.
  yp_string_owned_init(string, malloc(length), length);

  // This is the memory address where we're putting the unescaped string.
  char *dest = string->as.owned.source;
  size_t dest_length = 0;

  // This is the current position in the source string that we're looking at.
  // It's going to move along behind the backslash so that we can copy each
  // segment of the string that doesn't contain an escape.
  const char *cursor = value;
  const char *end = value + length;

  // For each escape found in the source string, we will handle it and update
  // the moving cursor->backslash window.
  while (backslash != NULL && backslash < end) {
    assert(dest_length < length);

    // This is the size of the segment of the string from the previous escape
    // or the start of the string to the current escape.
    size_t segment_size = (size_t) (backslash - cursor);

    // Here we're going to copy everything up until the escape into the
    // destination buffer.
    memcpy(dest + dest_length, cursor, segment_size);
    dest_length += segment_size;

    switch (backslash[1]) {
      case '\\':
      case '\'':
        dest[dest_length++] = (char) unescape_chars[(unsigned char) backslash[1]];
        cursor = backslash + 2;
        break;
      default:
        if (unescape_type == YP_UNESCAPE_MINIMAL) {
          // In this case we're escaping something that doesn't need escaping.
          dest[dest_length++] = '\\';
          cursor = backslash + 1;
          break;
        }

        // This is the only type of unescaping left. In this case we need to
        // handle all of the different unescapes.
        assert(unescape_type == YP_UNESCAPE_ALL);
        cursor = unescape(dest, &dest_length, backslash, end, error_list, YP_UNESCAPE_FLAG_NONE, true);
        break;
    }

    if (end > cursor) {
      backslash = memchr(cursor, '\\', (size_t) (end - cursor));
    } else {
      backslash = NULL;
    }
  }

  // We need to copy the final segment of the string after the last escape.
  if (end > cursor) {
    memcpy(dest + dest_length, cursor, (size_t) (end - cursor));
  } else {
    cursor = end;
  }

  // We also need to update the length at the end. This is because every escape
  // reduces the length of the final string, and we don't want garbage at the
  // end.
  string->as.owned.length = dest_length + ((size_t) (end - cursor));
}

// This function is similar to yp_unescape_manipulate_string, except it doesn't
// actually perform any string manipulations. Instead, it calculates how long
// the unescaped character is, and returns that value
__attribute__((__visibility__("default"))) extern size_t
yp_unescape_calculate_difference(const char *backslash, const char *end, yp_unescape_type_t unescape_type, bool expect_single_codepoint, yp_list_t *error_list) {
  assert(unescape_type != YP_UNESCAPE_NONE);

  switch (backslash[1]) {
    case '\\':
    case '\'':
      return 2;
    default: {
      if (unescape_type == YP_UNESCAPE_MINIMAL) return 2;

      // This is the only type of unescaping left. In this case we need to
      // handle all of the different unescapes.
      assert(unescape_type == YP_UNESCAPE_ALL);

      unsigned char flags = YP_UNESCAPE_FLAG_NONE;
      if (expect_single_codepoint)
        flags |= YP_UNESCAPE_FLAG_EXPECT_SINGLE;

      const char *cursor = unescape(NULL, 0, backslash, end, error_list, flags, false);
      assert(cursor > backslash);

      return (size_t) (cursor - backslash);
    }
  }
}
