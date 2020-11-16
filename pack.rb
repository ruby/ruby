# for pack.c

class Array
  #  call-seq:
  #     arr.pack( aTemplateString ) -> aBinaryString
  #     arr.pack( aTemplateString, buffer: aBufferString ) -> aBufferString
  #
  #  Packs the contents of <i>arr</i> into a binary sequence according to
  #  the directives in <i>aTemplateString</i> (see the table below)
  #  Directives ``A,'' ``a,'' and ``Z'' may be followed by a count,
  #  which gives the width of the resulting field. The remaining
  #  directives also may take a count, indicating the number of array
  #  elements to convert. If the count is an asterisk
  #  (``<code>*</code>''), all remaining array elements will be
  #  converted. Any of the directives ``<code>sSiIlL</code>'' may be
  #  followed by an underscore (``<code>_</code>'') or
  #  exclamation mark (``<code>!</code>'') to use the underlying
  #  platform's native size for the specified type; otherwise, they use a
  #  platform-independent size. Spaces are ignored in the template
  #  string. See also String#unpack.
  #
  #     a = [ "a", "b", "c" ]
  #     n = [ 65, 66, 67 ]
  #     a.pack("A3A3A3")   #=> "a  b  c  "
  #     a.pack("a3a3a3")   #=> "a\000\000b\000\000c\000\000"
  #     n.pack("ccc")      #=> "ABC"
  #
  #  If <i>aBufferString</i> is specified and its capacity is enough,
  #  +pack+ uses it as the buffer and returns it.
  #  When the offset is specified by the beginning of <i>aTemplateString</i>,
  #  the result is filled after the offset.
  #  If original contents of <i>aBufferString</i> exists and it's longer than
  #  the offset, the rest of <i>offsetOfBuffer</i> are overwritten by the result.
  #  If it's shorter, the gap is filled with ``<code>\0</code>''.
  #
  #  Note that ``buffer:'' option does not guarantee not to allocate memory
  #  in +pack+.  If the capacity of <i>aBufferString</i> is not enough,
  #  +pack+ allocates memory.
  #
  #  Directives for +pack+.
  #
  #   Integer       | Array   |
  #   Directive     | Element | Meaning
  #   ----------------------------------------------------------------------------
  #   C             | Integer | 8-bit unsigned (unsigned char)
  #   S             | Integer | 16-bit unsigned, native endian (uint16_t)
  #   L             | Integer | 32-bit unsigned, native endian (uint32_t)
  #   Q             | Integer | 64-bit unsigned, native endian (uint64_t)
  #   J             | Integer | pointer width unsigned, native endian (uintptr_t)
  #                 |         | (J is available since Ruby 2.3.)
  #                 |         |
  #   c             | Integer | 8-bit signed (signed char)
  #   s             | Integer | 16-bit signed, native endian (int16_t)
  #   l             | Integer | 32-bit signed, native endian (int32_t)
  #   q             | Integer | 64-bit signed, native endian (int64_t)
  #   j             | Integer | pointer width signed, native endian (intptr_t)
  #                 |         | (j is available since Ruby 2.3.)
  #                 |         |
  #   S_ S!         | Integer | unsigned short, native endian
  #   I I_ I!       | Integer | unsigned int, native endian
  #   L_ L!         | Integer | unsigned long, native endian
  #   Q_ Q!         | Integer | unsigned long long, native endian (ArgumentError
  #                 |         | if the platform has no long long type.)
  #                 |         | (Q_ and Q! is available since Ruby 2.1.)
  #   J!            | Integer | uintptr_t, native endian (same with J)
  #                 |         | (J! is available since Ruby 2.3.)
  #                 |         |
  #   s_ s!         | Integer | signed short, native endian
  #   i i_ i!       | Integer | signed int, native endian
  #   l_ l!         | Integer | signed long, native endian
  #   q_ q!         | Integer | signed long long, native endian (ArgumentError
  #                 |         | if the platform has no long long type.)
  #                 |         | (q_ and q! is available since Ruby 2.1.)
  #   j!            | Integer | intptr_t, native endian (same with j)
  #                 |         | (j! is available since Ruby 2.3.)
  #                 |         |
  #   S> s> S!> s!> | Integer | same as the directives without ">" except
  #   L> l> L!> l!> |         | big endian
  #   I!> i!>       |         | (available since Ruby 1.9.3)
  #   Q> q> Q!> q!> |         | "S>" is same as "n"
  #   J> j> J!> j!> |         | "L>" is same as "N"
  #                 |         |
  #   S< s< S!< s!< | Integer | same as the directives without "<" except
  #   L< l< L!< l!< |         | little endian
  #   I!< i!<       |         | (available since Ruby 1.9.3)
  #   Q< q< Q!< q!< |         | "S<" is same as "v"
  #   J< j< J!< j!< |         | "L<" is same as "V"
  #                 |         |
  #   n             | Integer | 16-bit unsigned, network (big-endian) byte order
  #   N             | Integer | 32-bit unsigned, network (big-endian) byte order
  #   v             | Integer | 16-bit unsigned, VAX (little-endian) byte order
  #   V             | Integer | 32-bit unsigned, VAX (little-endian) byte order
  #                 |         |
  #   U             | Integer | UTF-8 character
  #   w             | Integer | BER-compressed integer
  #
  #   Float        | Array   |
  #   Directive    | Element | Meaning
  #   ---------------------------------------------------------------------------
  #   D d          | Float   | double-precision, native format
  #   F f          | Float   | single-precision, native format
  #   E            | Float   | double-precision, little-endian byte order
  #   e            | Float   | single-precision, little-endian byte order
  #   G            | Float   | double-precision, network (big-endian) byte order
  #   g            | Float   | single-precision, network (big-endian) byte order
  #
  #   String       | Array   |
  #   Directive    | Element | Meaning
  #   ---------------------------------------------------------------------------
  #   A            | String  | arbitrary binary string (space padded, count is width)
  #   a            | String  | arbitrary binary string (null padded, count is width)
  #   Z            | String  | same as ``a'', except that null is added with *
  #   B            | String  | bit string (MSB first)
  #   b            | String  | bit string (LSB first)
  #   H            | String  | hex string (high nibble first)
  #   h            | String  | hex string (low nibble first)
  #   u            | String  | UU-encoded string
  #   M            | String  | quoted printable, MIME encoding (see also RFC2045)
  #                |         | (text mode but input must use LF and output LF)
  #   m            | String  | base64 encoded string (see RFC 2045)
  #                |         | (if count is 0, no line feed are added, see RFC 4648)
  #                |         | (count specifies input bytes between each LF,
  #                |         | rounded down to nearest multiple of 3)
  #   P            | String  | pointer to a structure (fixed-length string)
  #   p            | String  | pointer to a null-terminated string
  #
  #   Misc.        | Array   |
  #   Directive    | Element | Meaning
  #   ---------------------------------------------------------------------------
  #   @            | ---     | moves to absolute position
  #   X            | ---     | back up a byte
  #   x            | ---     | null byte
  def pack(fmt, buffer: nil)
    Primitive.pack_pack(fmt, buffer)
  end
end

class String
  # call-seq:
  #    str.unpack(format)    ->  anArray
  #
  # Decodes <i>str</i> (which may contain binary data) according to the
  # format string, returning an array of each value extracted. The
  # format string consists of a sequence of single-character directives,
  # summarized in the table at the end of this entry.
  # Each directive may be followed
  # by a number, indicating the number of times to repeat with this
  # directive. An asterisk (``<code>*</code>'') will use up all
  # remaining elements. The directives <code>sSiIlL</code> may each be
  # followed by an underscore (``<code>_</code>'') or
  # exclamation mark (``<code>!</code>'') to use the underlying
  # platform's native size for the specified type; otherwise, it uses a
  # platform-independent consistent size. Spaces are ignored in the
  # format string. See also String#unpack1,  Array#pack.
  #
  #    "abc \0\0abc \0\0".unpack('A6Z6')   #=> ["abc", "abc "]
  #    "abc \0\0".unpack('a3a3')           #=> ["abc", " \000\000"]
  #    "abc \0abc \0".unpack('Z*Z*')       #=> ["abc ", "abc "]
  #    "aa".unpack('b8B8')                 #=> ["10000110", "01100001"]
  #    "aaa".unpack('h2H2c')               #=> ["16", "61", 97]
  #    "\xfe\xff\xfe\xff".unpack('sS')     #=> [-2, 65534]
  #    "now=20is".unpack('M*')             #=> ["now is"]
  #    "whole".unpack('xax2aX2aX1aX2a')    #=> ["h", "e", "l", "l", "o"]
  #
  # This table summarizes the various formats and the Ruby classes
  # returned by each.
  #
  #  Integer       |         |
  #  Directive     | Returns | Meaning
  #  ------------------------------------------------------------------
  #  C             | Integer | 8-bit unsigned (unsigned char)
  #  S             | Integer | 16-bit unsigned, native endian (uint16_t)
  #  L             | Integer | 32-bit unsigned, native endian (uint32_t)
  #  Q             | Integer | 64-bit unsigned, native endian (uint64_t)
  #  J             | Integer | pointer width unsigned, native endian (uintptr_t)
  #                |         |
  #  c             | Integer | 8-bit signed (signed char)
  #  s             | Integer | 16-bit signed, native endian (int16_t)
  #  l             | Integer | 32-bit signed, native endian (int32_t)
  #  q             | Integer | 64-bit signed, native endian (int64_t)
  #  j             | Integer | pointer width signed, native endian (intptr_t)
  #                |         |
  #  S_ S!         | Integer | unsigned short, native endian
  #  I I_ I!       | Integer | unsigned int, native endian
  #  L_ L!         | Integer | unsigned long, native endian
  #  Q_ Q!         | Integer | unsigned long long, native endian (ArgumentError
  #                |         | if the platform has no long long type.)
  #  J!            | Integer | uintptr_t, native endian (same with J)
  #                |         |
  #  s_ s!         | Integer | signed short, native endian
  #  i i_ i!       | Integer | signed int, native endian
  #  l_ l!         | Integer | signed long, native endian
  #  q_ q!         | Integer | signed long long, native endian (ArgumentError
  #                |         | if the platform has no long long type.)
  #  j!            | Integer | intptr_t, native endian (same with j)
  #                |         |
  #  S> s> S!> s!> | Integer | same as the directives without ">" except
  #  L> l> L!> l!> |         | big endian
  #  I!> i!>       |         |
  #  Q> q> Q!> q!> |         | "S>" is same as "n"
  #  J> j> J!> j!> |         | "L>" is same as "N"
  #                |         |
  #  S< s< S!< s!< | Integer | same as the directives without "<" except
  #  L< l< L!< l!< |         | little endian
  #  I!< i!<       |         |
  #  Q< q< Q!< q!< |         | "S<" is same as "v"
  #  J< j< J!< j!< |         | "L<" is same as "V"
  #                |         |
  #  n             | Integer | 16-bit unsigned, network (big-endian) byte order
  #  N             | Integer | 32-bit unsigned, network (big-endian) byte order
  #  v             | Integer | 16-bit unsigned, VAX (little-endian) byte order
  #  V             | Integer | 32-bit unsigned, VAX (little-endian) byte order
  #                |         |
  #  U             | Integer | UTF-8 character
  #  w             | Integer | BER-compressed integer (see Array#pack)
  #
  #  Float        |         |
  #  Directive    | Returns | Meaning
  #  -----------------------------------------------------------------
  #  D d          | Float   | double-precision, native format
  #  F f          | Float   | single-precision, native format
  #  E            | Float   | double-precision, little-endian byte order
  #  e            | Float   | single-precision, little-endian byte order
  #  G            | Float   | double-precision, network (big-endian) byte order
  #  g            | Float   | single-precision, network (big-endian) byte order
  #
  #  String       |         |
  #  Directive    | Returns | Meaning
  #  -----------------------------------------------------------------
  #  A            | String  | arbitrary binary string (remove trailing nulls and ASCII spaces)
  #  a            | String  | arbitrary binary string
  #  Z            | String  | null-terminated string
  #  B            | String  | bit string (MSB first)
  #  b            | String  | bit string (LSB first)
  #  H            | String  | hex string (high nibble first)
  #  h            | String  | hex string (low nibble first)
  #  u            | String  | UU-encoded string
  #  M            | String  | quoted-printable, MIME encoding (see RFC2045)
  #  m            | String  | base64 encoded string (RFC 2045) (default)
  #               |         | base64 encoded string (RFC 4648) if followed by 0
  #  P            | String  | pointer to a structure (fixed-length string)
  #  p            | String  | pointer to a null-terminated string
  #
  #  Misc.        |         |
  #  Directive    | Returns | Meaning
  #  -----------------------------------------------------------------
  #  @            | ---     | skip to the offset given by the length argument
  #  X            | ---     | skip backward one byte
  #  x            | ---     | skip forward one byte
  #
  # HISTORY
  #
  # * J, J! j, and j! are available since Ruby 2.3.
  # * Q_, Q!, q_, and q! are available since Ruby 2.1.
  # * I!<, i!<, I!>, and i!> are available since Ruby 1.9.3.
  def unpack(fmt)
    Primitive.pack_unpack(fmt)
  end

  # call-seq:
  #    str.unpack1(format)    ->  obj
  #
  # Decodes <i>str</i> (which may contain binary data) according to the
  # format string, returning the first value extracted.
  # See also String#unpack, Array#pack.
  #
  # Contrast with String#unpack:
  #
  #    "abc \0\0abc \0\0".unpack('A6Z6')   #=> ["abc", "abc "]
  #    "abc \0\0abc \0\0".unpack1('A6Z6')  #=> "abc"
  #
  # In that case data would be lost but often it's the case that the array
  # only holds one value, especially when unpacking binary data. For instance:
  #
  # "\xff\x00\x00\x00".unpack("l")         #=>  [255]
  # "\xff\x00\x00\x00".unpack1("l")        #=>  255
  #
  # Thus unpack1 is convenient, makes clear the intention and signals
  # the expected return value to those reading the code.
  def unpack1(fmt)
    Primitive.pack_unpack1(fmt)
  end
end
