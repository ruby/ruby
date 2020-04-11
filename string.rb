class String
  #
  #  call-seq:
  #     str.each_line(separator=$/, chomp: false) {|substr| block } -> str
  #     str.each_line(separator=$/, chomp: false)                   -> an_enumerator
  #
  #  Splits <i>str</i> using the supplied parameter as the record
  #  separator (<code>$/</code> by default), passing each substring in
  #  turn to the supplied block.  If a zero-length record separator is
  #  supplied, the string is split into paragraphs delimited by
  #  multiple successive newlines.
  #
  #  If +chomp+ is +true+, +separator+ will be removed from the end of each
  #  line.
  #
  #  If no block is given, an enumerator is returned instead.
  #
  #     "hello\nworld".each_line {|s| p s}
  #     # prints:
  #     #   "hello\n"
  #     #   "world"
  #
  #     "hello\nworld".each_line('l') {|s| p s}
  #     # prints:
  #     #   "hel"
  #     #   "l"
  #     #   "o\nworl"
  #     #   "d"
  #
  #     "hello\n\n\nworld".each_line('') {|s| p s}
  #     # prints
  #     #   "hello\n\n"
  #     #   "world"
  #
  #     "hello\nworld".each_line(chomp: true) {|s| p s}
  #     # prints:
  #     #   "hello"
  #     #   "world"
  #
  #     "hello\nworld".each_line('l', chomp: true) {|s| p s}
  #     # prints:
  #     #   "he"
  #     #   ""
  #     #   "o\nwor"
  #     #   "d"
  #
  #
  def each_line(rs = $/, chomp: false)
    __builtin_rb_str_each_line(rs, chomp)
  end
  #
  #  call-seq:
  #     str.lines(separator=$/, chomp: false)  -> an_array
  #
  #  Returns an array of lines in <i>str</i> split using the supplied
  #  record separator (<code>$/</code> by default).  This is a
  #  shorthand for <code>str.each_line(separator, getline_args).to_a</code>.
  #
  #  If +chomp+ is +true+, +separator+ will be removed from the end of each
  #  line.
  #
  #     "hello\nworld\n".lines              #=> ["hello\n", "world\n"]
  #     "hello  world".lines(' ')           #=> ["hello ", " ", "world"]
  #     "hello\nworld\n".lines(chomp: true) #=> ["hello", "world"]
  #
  #  If a block is given, which is a deprecated form, works the same as
  #  <code>each_line</code>.
  #
  def lines(rs = $/, chomp: false)
    __builtin_rb_str_lines(rs, chomp)
  end
end
