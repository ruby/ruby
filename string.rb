#  A \String object has an arbitrary sequence of bytes,
#  typically representing text or binary data.
#  A \String object may be created using String::new or as literals.
#
#  String objects differ from Symbol objects in that Symbol objects are
#  designed to be used as identifiers, instead of text or data.
#
#  You can create a \String object explicitly with:
#
#  - A {string literal}[rdoc-ref:syntax/literals.rdoc@String+Literals].
#  - A {heredoc literal}[rdoc-ref:syntax/literals.rdoc@Here+Document+Literals].
#
#  You can convert certain objects to Strings with:
#
#  - \Method #String.
#
#  Some \String methods modify +self+.
#  Typically, a method whose name ends with <tt>!</tt> modifies +self+
#  and returns +self+;
#  often a similarly named method (without the <tt>!</tt>)
#  returns a new string.
#
#  In general, if there exist both bang and non-bang version of method,
#  the bang! mutates and the non-bang! does not.
#  However, a method without a bang can also mutate, such as String#replace.
#
#  == Substitution Methods
#
#  These methods perform substitutions:
#
#  - String#sub: One substitution (or none); returns a new string.
#  - String#sub!: One substitution (or none); returns +self+.
#  - String#gsub: Zero or more substitutions; returns a new string.
#  - String#gsub!: Zero or more substitutions; returns +self+.
#
#  Each of these methods takes:
#
#  - A first argument, +pattern+ (string or regexp),
#    that specifies the substring(s) to be replaced.
#
#  - Either of these:
#
#    - A second argument, +replacement+ (string or hash),
#      that determines the replacing string.
#    - A block that will determine the replacing string.
#
#  The examples in this section mostly use methods String#sub and String#gsub;
#  the principles illustrated apply to all four substitution methods.
#
#  <b>Argument +pattern+</b>
#
#  Argument +pattern+ is commonly a regular expression:
#
#    s = 'hello'
#    s.sub(/[aeiou]/, '*')# => "h*llo"
#    s.gsub(/[aeiou]/, '*') # => "h*ll*"
#    s.gsub(/[aeiou]/, '')# => "hll"
#    s.sub(/ell/, 'al')   # => "halo"
#    s.gsub(/xyzzy/, '*') # => "hello"
#    'THX1138'.gsub(/\d+/, '00') # => "THX00"
#
#  When +pattern+ is a string, all its characters are treated
#  as ordinary characters (not as regexp special characters):
#
#    'THX1138'.gsub('\d+', '00') # => "THX1138"
#
#  <b>\String +replacement+</b>
#
#  If +replacement+ is a string, that string will determine
#  the replacing string that is to be substituted for the matched text.
#
#  Each of the examples above uses a simple string as the replacing string.
#
#  \String +replacement+ may contain back-references to the pattern's captures:
#
#  - <tt>\n</tt> (_n_ a non-negative integer) refers to <tt>$n</tt>.
#  - <tt>\k<name></tt> refers to the named capture +name+.
#
#  See rdoc-ref:regexp.rdoc for details.
#
#  Note that within the string +replacement+, a character combination
#  such as <tt>$&</tt> is treated as ordinary text, and not as
#  a special match variable.
#  However, you may refer to some special match variables using these
#  combinations:
#
#  - <tt>\&</tt> and <tt>\0</tt> correspond to <tt>$&</tt>,
#    which contains the complete matched text.
#  - <tt>\'</tt> corresponds to <tt>$'</tt>,
#    which contains string after match.
#  - <tt>\`</tt> corresponds to <tt>$`</tt>,
#    which contains string before match.
#  - <tt>\+</tt> corresponds to <tt>$+</tt>,
#    which contains last capture group.
#
#  See rdoc-ref:regexp.rdoc for details.
#
#  Note that <tt>\\\\</tt> is interpreted as an escape, i.e., a single backslash.
#
#  Note also that a string literal consumes backslashes.
#  See {String Literals}[rdoc-ref:syntax/literals.rdoc@String+Literals] for details about string literals.
#
#  A back-reference is typically preceded by an additional backslash.
#  For example, if you want to write a back-reference <tt>\&</tt> in
#  +replacement+ with a double-quoted string literal, you need to write
#  <tt>"..\\\\&.."</tt>.
#
#  If you want to write a non-back-reference string <tt>\&</tt> in
#  +replacement+, you need first to escape the backslash to prevent
#  this method from interpreting it as a back-reference, and then you
#  need to escape the backslashes again to prevent a string literal from
#  consuming them: <tt>"..\\\\\\\\&.."</tt>.
#
#  You may want to use the block form to avoid a lot of backslashes.
#
#  <b>\Hash +replacement+</b>
#
#  If argument +replacement+ is a hash, and +pattern+ matches one of its keys,
#  the replacing string is the value for that key:
#
#    h = {'foo' => 'bar', 'baz' => 'bat'}
#    'food'.sub('foo', h) # => "bard"
#
#  Note that a symbol key does not match:
#
#    h = {foo: 'bar', baz: 'bat'}
#    'food'.sub('foo', h) # => "d"
#
#  <b>Block</b>
#
#  In the block form, the current match string is passed to the block;
#  the block's return value becomes the replacing string:
#
#    s = '@'
#   '1234'.gsub(/\d/) {|match| s.succ! } # => "ABCD"
#
#  Special match variables such as <tt>$1</tt>, <tt>$2</tt>, <tt>$`</tt>,
#  <tt>$&</tt>, and <tt>$'</tt> are set appropriately.
#
#  == Whitespace in Strings
#
#  In class \String, _whitespace_ is defined as a contiguous sequence of characters
#  consisting of any mixture of the following:
#
#  - NL (null): <tt>"\x00"</tt>, <tt>"\u0000"</tt>.
#  - HT (horizontal tab): <tt>"\x09"</tt>, <tt>"\t"</tt>.
#  - LF (line feed): <tt>"\x0a"</tt>, <tt>"\n"</tt>.
#  - VT (vertical tab): <tt>"\x0b"</tt>, <tt>"\v"</tt>.
#  - FF (form feed): <tt>"\x0c"</tt>, <tt>"\f"</tt>.
#  - CR (carriage return): <tt>"\x0d"</tt>, <tt>"\r"</tt>.
#  - SP (space): <tt>"\x20"</tt>, <tt>" "</tt>.
#
#
#  Whitespace is relevant for these methods:
#
#  - #lstrip, #lstrip!: strip leading whitespace.
#  - #rstrip, #rstrip!: strip trailing whitespace.
#  - #strip, #strip!: strip leading and trailing whitespace.
#
#  == \String Slices
#
#  A _slice_ of a string is a substring that is selected by certain criteria.
#
#  These instance methods make use of slicing:
#
#  - String#[] (also aliased as String#slice) returns a slice copied from +self+.
#  - String#[]= returns a copy of +self+ with a slice replaced.
#  - String#slice! returns +self+ with a slice removed.
#
#  Each of the above methods takes arguments that determine the slice
#  to be copied or replaced.
#
#  The arguments have several forms.
#  For string +string+,  the forms are:
#
#  - <tt>string[index]</tt>.
#  - <tt>string[start, length]</tt>.
#  - <tt>string[range]</tt>.
#  - <tt>string[regexp, capture = 0]</tt>.
#  - <tt>string[substring]</tt>.
#
#  <b><tt>string[index]</tt></b>
#
#  When non-negative integer argument +index+ is given,
#  the slice is the 1-character substring found in +self+ at character offset +index+:
#
#    'bar'[0]       # => "b"
#    'bar'[2]       # => "r"
#    'bar'[20]      # => nil
#    'тест'[2]      # => "с"
#    'こんにちは'[4]  # => "は"
#
#  When negative integer +index+ is given,
#  the slice begins at the offset given by counting backward from the end of +self+:
#
#    'bar'[-3]         # => "b"
#    'bar'[-1]         # => "r"
#    'bar'[-20]        # => nil
#
#  <b><tt>string[start, length]</tt></b>
#
#  When non-negative integer arguments +start+ and +length+ are given,
#  the slice begins at character offset +start+, if it exists,
#  and continues for +length+ characters, if available:
#
#    'foo'[0, 2]       # => "fo"
#    'тест'[1, 2]      # => "ес"
#    'こんにちは'[2, 2]  # => "にち"
#    # Zero length.
#    'foo'[2, 0]       # => ""
#    # Length not entirely available.
#    'foo'[1, 200]     # => "oo"
#    # Start out of range.
#    'foo'[4, 2]      # => nil
#
#  Special case: if +start+ is equal to the length of +self+,
#  the slice is a new empty string:
#
#    'foo'[3, 2]   # => ""
#    'foo'[3, 200] # => ""
#
#  When negative +start+ and non-negative +length+ are given,
#  the slice beginning is determined by counting backward from the end of +self+,
#  and the slice continues for +length+ characters, if available:
#
#    'foo'[-2, 2]    # => "oo"
#    'foo'[-2, 200]  # => "oo"
#    # Start out of range.
#    'foo'[-4, 2]     # => nil
#
#  When negative +length+ is given, there is no slice:
#
#    'foo'[1, -1]  # => nil
#    'foo'[-2, -1] # => nil
#
#  <b><tt>string[range]</tt></b>
#
#  When Range argument +range+ is given,
#  creates a substring of +string+ using the indices in +range+.
#  The slice is then determined as above:
#
#    'foo'[0..1]    # => "fo"
#    'foo'[0, 2]    # => "fo"
#
#    'foo'[2...2]   # => ""
#    'foo'[2, 0]    # => ""
#
#    'foo'[1..200]  # => "oo"
#    'foo'[1, 200]  # => "oo"
#
#    'foo'[4..5]    # => nil
#    'foo'[4, 2]    # => nil
#
#    'foo'[-4..-3]  # => nil
#    'foo'[-4, 2]   # => nil
#
#    'foo'[3..4]    # => ""
#    'foo'[3, 2]    # => ""
#
#    'foo'[-2..-1]  # => "oo"
#    'foo'[-2, 2]   # => "oo"
#
#    'foo'[-2..197] # => "oo"
#    'foo'[-2, 200] # => "oo"
#
#  <b><tt>string[regexp, capture = 0]</tt></b>
#
#  When the \Regexp argument +regexp+ is given,
#  and the +capture+ argument is <tt>0</tt>,
#  the slice is the first matching substring found in +self+:
#
#    'foo'[/o/] # => "o"
#    'foo'[/x/] # => nil
#    s = 'hello there'
#    s[/[aeiou](.)\1/] # => "ell"
#    s[/[aeiou](.)\1/, 0] # => "ell"
#
#  If argument +capture+ is given and not <tt>0</tt>,
#  it should be either an capture group index (integer)
#  or a capture group name (string or symbol);
#  the slice is the specified capture (see Regexp@Capturing):
#
#    s = 'hello there'
#    s[/[aeiou](.)\1/, 1] # => "l"
#    s[/(?<vowel>[aeiou])(?<non_vowel>[^aeiou])/, "non_vowel"] # => "l"
#    s[/(?<vowel>[aeiou])(?<non_vowel>[^aeiou])/, :vowel] # => "e"
#
#  If an invalid capture group index is given, there is no slice.
#  If an invalid capture group name is given, +IndexError+ is raised.
#
#  <b><tt>string[substring]</tt></b>
#
#  When the single \String argument +substring+ is given,
#  returns the substring from +self+ if found, otherwise +nil+:
#
#    'foo'['oo'] # => "oo"
#    'foo'['xx'] # => nil
#
#  == What's Here
#
#  First, what's elsewhere. \Class \String:
#
#  - Inherits from {class Object}[rdoc-ref:Object@What-27s+Here].
#  - Includes {module Comparable}[rdoc-ref:Comparable@What-27s+Here].
#
#  Here, class \String provides methods that are useful for:
#
#  - {Creating a String}[rdoc-ref:String@Methods+for+Creating+a+String]
#  - {Frozen/Unfrozen Strings}[rdoc-ref:String@Methods+for+a+Frozen-2FUnfrozen+String]
#  - {Querying}[rdoc-ref:String@Methods+for+Querying]
#  - {Comparing}[rdoc-ref:String@Methods+for+Comparing]
#  - {Modifying a String}[rdoc-ref:String@Methods+for+Modifying+a+String]
#  - {Converting to New String}[rdoc-ref:String@Methods+for+Converting+to+New+String]
#  - {Converting to Non-String}[rdoc-ref:String@Methods+for+Converting+to+Non--5CString]
#  - {Iterating}[rdoc-ref:String@Methods+for+Iterating]
#
#  === Methods for Creating a \String
#
#  - ::new: Returns a new string.
#  - ::try_convert: Returns a new string created from a given object.
#
#  === Methods for a Frozen/Unfrozen String
#
#  - #+@: Returns a string that is not frozen: +self+, if not frozen;
#    +self.dup+ otherwise.
#  - #-@: Returns a string that is frozen: +self+, if already frozen;
#    +self.freeze+ otherwise.
#  - #freeze: Freezes +self+, if not already frozen; returns +self+.
#
#  === Methods for Querying
#
#  _Counts_
#
#  - #length, #size: Returns the count of characters (not bytes).
#  - #empty?: Returns +true+ if +self.length+ is zero; +false+ otherwise.
#  - #bytesize: Returns the count of bytes.
#  - #count: Returns the count of substrings matching given strings.
#
#  _Substrings_
#
#  - #=~: Returns the index of the first substring that matches a given
#    Regexp or other object; returns +nil+ if no match is found.
#  - #index: Returns the index of the _first_ occurrence of a given substring;
#    returns +nil+ if none found.
#  - #rindex: Returns the index of the _last_ occurrence of a given substring;
#    returns +nil+ if none found.
#  - #include?: Returns +true+ if the string contains a given substring; +false+ otherwise.
#  - #match: Returns a MatchData object if the string matches a given Regexp; +nil+ otherwise.
#  - #match?: Returns +true+ if the string matches a given Regexp; +false+ otherwise.
#  - #start_with?: Returns +true+ if the string begins with any of the given substrings.
#  - #end_with?: Returns +true+ if the string ends with any of the given substrings.
#
#  _Encodings_
#
#  - #encoding\: Returns the Encoding object that represents the encoding of the string.
#  - #unicode_normalized?: Returns +true+ if the string is in Unicode normalized form; +false+ otherwise.
#  - #valid_encoding?: Returns +true+ if the string contains only characters that are valid
#    for its encoding.
#  - #ascii_only?: Returns +true+ if the string has only ASCII characters; +false+ otherwise.
#
#  _Other_
#
#  - #sum: Returns a basic checksum for the string: the sum of each byte.
#  - #hash: Returns the integer hash code.
#
#  === Methods for Comparing
#
#  - #==, #===: Returns +true+ if a given other string has the same content as +self+.
#  - #eql?: Returns +true+ if the content is the same as the given other string.
#  - #<=>: Returns -1, 0, or 1 as a given other string is smaller than,
#    equal to, or larger than +self+.
#  - #casecmp: Ignoring case, returns -1, 0, or 1 as a given
#    other string is smaller than, equal to, or larger than +self+.
#  - #casecmp?: Returns +true+ if the string is equal to a given string after Unicode case folding;
#    +false+ otherwise.
#
#  === Methods for Modifying a \String
#
#  Each of these methods modifies +self+.
#
#  _Insertion_
#
#  - #insert: Returns +self+ with a given string inserted at a given offset.
#  - #<<: Returns +self+ concatenated with a given string or integer.
#
#  _Substitution_
#
#  - #sub!: Replaces the first substring that matches a given pattern with a given replacement string;
#    returns +self+ if any changes, +nil+ otherwise.
#  - #gsub!: Replaces each substring that matches a given pattern with a given replacement string;
#    returns +self+ if any changes, +nil+ otherwise.
#  - #succ!, #next!: Returns +self+ modified to become its own successor.
#  - #replace: Returns +self+ with its entire content replaced by a given string.
#  - #reverse!: Returns +self+ with its characters in reverse order.
#  - #setbyte: Sets the byte at a given integer offset to a given value; returns the argument.
#  - #tr!: Replaces specified characters in +self+ with specified replacement characters;
#    returns +self+ if any changes, +nil+ otherwise.
#  - #tr_s!: Replaces specified characters in +self+ with specified replacement characters,
#    removing duplicates from the substrings that were modified;
#    returns +self+ if any changes, +nil+ otherwise.
#
#  _Casing_
#
#  - #capitalize!: Upcases the initial character and downcases all others;
#    returns +self+ if any changes, +nil+ otherwise.
#  - #downcase!: Downcases all characters; returns +self+ if any changes, +nil+ otherwise.
#  - #upcase!: Upcases all characters; returns +self+ if any changes, +nil+ otherwise.
#  - #swapcase!: Upcases each downcase character and downcases each upcase character;
#    returns +self+ if any changes, +nil+ otherwise.
#
#  _Encoding_
#
#  - #encode!: Returns +self+ with all characters transcoded from one given encoding into another.
#  - #unicode_normalize!: Unicode-normalizes +self+; returns +self+.
#  - #scrub!: Replaces each invalid byte with a given character; returns +self+.
#  - #force_encoding: Changes the encoding to a given encoding; returns +self+.
#
#  _Deletion_
#
#  - #clear: Removes all content, so that +self+ is empty; returns +self+.
#  - #slice!, #[]=: Removes a substring determined by a given index, start/length, range, regexp, or substring.
#  - #squeeze!: Removes contiguous duplicate characters; returns +self+.
#  - #delete!: Removes characters as determined by the intersection of substring arguments.
#  - #lstrip!: Removes leading whitespace; returns +self+ if any changes, +nil+ otherwise.
#  - #rstrip!: Removes trailing whitespace; returns +self+ if any changes, +nil+ otherwise.
#  - #strip!: Removes leading and trailing whitespace; returns +self+ if any changes, +nil+ otherwise.
#  - #chomp!: Removes trailing record separator, if found; returns +self+ if any changes, +nil+ otherwise.
#  - #chop!: Removes trailing newline characters if found; otherwise removes the last character;
#    returns +self+ if any changes, +nil+ otherwise.
#
#  === Methods for Converting to New \String
#
#  Each of these methods returns a new \String based on +self+,
#  often just a modified copy of +self+.
#
#  _Extension_
#
#  - #*: Returns the concatenation of multiple copies of +self+,
#  - #+: Returns the concatenation of +self+ and a given other string.
#  - #center: Returns a copy of +self+ centered between pad substring.
#  - #concat: Returns the concatenation of +self+ with given other strings.
#  - #prepend: Returns the concatenation of a given other string with +self+.
#  - #ljust: Returns a copy of +self+ of a given length, right-padded with a given other string.
#  - #rjust: Returns a copy of +self+ of a given length, left-padded with a given other string.
#
#  _Encoding_
#
#  - #b: Returns a copy of +self+ with ASCII-8BIT encoding.
#  - #scrub: Returns a copy of +self+ with each invalid byte replaced with a given character.
#  - #unicode_normalize: Returns a copy of +self+ with each character Unicode-normalized.
#  - #encode: Returns a copy of +self+ with all characters transcoded from one given encoding into another.
#
#  _Substitution_
#
#  - #dump: Returns a copy of +self+ with all non-printing characters replaced by \xHH notation
#    and all special characters escaped.
#  - #undump: Returns a copy of +self+ with all <tt>\xNN</tt> notation replace by <tt>\uNNNN</tt> notation
#    and all escaped characters unescaped.
#  - #sub: Returns a copy of +self+ with the first substring matching a given pattern
#    replaced with a given replacement string;.
#  - #gsub: Returns a copy of +self+ with each substring that matches a given pattern
#    replaced with a given replacement string.
#  - #succ, #next: Returns the string that is the successor to +self+.
#  - #reverse: Returns a copy of +self+ with its characters in reverse order.
#  - #tr: Returns a copy of +self+ with specified characters replaced with specified      replacement characters.
#  - #tr_s: Returns a copy of +self+ with specified characters replaced with
#    specified replacement characters,
#    removing duplicates from the substrings that were modified.
#  - #%: Returns the string resulting from formatting a given object into +self+
#
#  _Casing_
#
#  - #capitalize: Returns a copy of +self+ with the first character upcased
#    and all other characters downcased.
#  - #downcase: Returns a copy of +self+ with all characters downcased.
#  - #upcase: Returns a copy of +self+ with all characters upcased.
#  - #swapcase: Returns a copy of +self+ with all upcase characters downcased
#    and all downcase characters upcased.
#
#  _Deletion_
#
#  - #delete: Returns a copy of +self+ with characters removed
#  - #delete_prefix: Returns a copy of +self+ with a given prefix removed.
#  - #delete_suffix: Returns a copy of +self+ with a given suffix removed.
#  - #lstrip: Returns a copy of +self+ with leading whitespace removed.
#  - #rstrip: Returns a copy of +self+ with trailing whitespace removed.
#  - #strip: Returns a copy of +self+ with leading and trailing whitespace removed.
#  - #chomp: Returns a copy of +self+ with a trailing record separator removed, if found.
#  - #chop: Returns a copy of +self+ with trailing newline characters or the last character removed.
#  - #squeeze: Returns a copy of +self+ with contiguous duplicate characters removed.
#  - #[], #slice: Returns a substring determined by a given index, start/length, or range, or string.
#  - #byteslice: Returns a substring determined by a given index, start/length, or range.
#  - #chr: Returns the first character.
#
#  _Duplication_
#
#  - #to_s, $to_str: If +self+ is a subclass of \String, returns +self+ copied into a \String;
#    otherwise, returns +self+.
#
#  === Methods for Converting to Non-\String
#
#  Each of these methods converts the contents of +self+ to a non-\String.
#
#  <em>Characters, Bytes, and Clusters</em>
#
#  - #bytes: Returns an array of the bytes in +self+.
#  - #chars: Returns an array of the characters in +self+.
#  - #codepoints: Returns an array of the integer ordinals in +self+.
#  - #getbyte: Returns an integer byte as determined by a given index.
#  - #grapheme_clusters: Returns an array of the grapheme clusters in +self+.
#
#  _Splitting_
#
#  - #lines: Returns an array of the lines in +self+, as determined by a given record separator.
#  - #partition: Returns a 3-element array determined by the first substring that matches
#    a given substring or regexp,
#  - #rpartition: Returns a 3-element array determined by the last substring that matches
#    a given substring or regexp,
#  - #split: Returns an array of substrings determined by a given delimiter -- regexp or string --
#    or, if a block given, passes those substrings to the block.
#
#  _Matching_
#
#  - #scan: Returns an array of substrings matching a given regexp or string, or,
#    if a block given, passes each matching substring to the  block.
#  - #unpack: Returns an array of substrings extracted from +self+ according to a given format.
#  - #unpack1: Returns the first substring extracted from +self+ according to a given format.
#
#  _Numerics_
#
#  - #hex: Returns the integer value of the leading characters, interpreted as hexadecimal digits.
#  - #oct: Returns the integer value of the leading characters, interpreted as octal digits.
#  - #ord: Returns the integer ordinal of the first character in +self+.
#  - #to_i: Returns the integer value of leading characters, interpreted as an integer.
#  - #to_f: Returns the floating-point value of leading characters, interpreted as a floating-point number.
#
#  <em>Strings and Symbols</em>
#
#  - #inspect: Returns copy of +self+, enclosed in double-quotes, with special characters escaped.
#  - #to_sym, #intern: Returns the symbol corresponding to +self+.
#
#  === Methods for Iterating
#
#  - #each_byte: Calls the given block with each successive byte in +self+.
#  - #each_char: Calls the given block with each successive character in +self+.
#  - #each_codepoint: Calls the given block with each successive integer codepoint in +self+.
#  - #each_grapheme_cluster: Calls the given block with each successive grapheme cluster in +self+.
#  - #each_line: Calls the given block with each successive line in +self+,
#    as determined by a given record separator.
#  - #upto: Calls the given block with each string value returned by successive calls to #succ.

class String; end
