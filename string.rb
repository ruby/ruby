class String
  #  call-seq:
  #    valid_encoding? -> true or false
  #
  #  :include: doc/string/valid_encoding_p.rdoc
  #
  def valid_encoding?
    Primitive.attr! :leaf
    Primitive.cexpr! 'rb_str_valid_encoding_p(self)'
  end

  #  call-seq:
  #    ascii_only? -> true or false
  #
  #  Returns whether +self+ contains only ASCII characters:
  #
  #    'abc'.ascii_only?         # => true
  #    "abc\u{6666}".ascii_only? # => false
  #
  #  Related: see {Querying}[rdoc-ref:String@Querying].
  def ascii_only?
    Primitive.attr! :leaf
    Primitive.cexpr! 'rb_str_is_ascii_only_p(self)'
  end

  #  call-seq:
  #    String.new(string = ''.encode(Encoding::ASCII_8BIT), **options) -> new_string
  #
  #  :include: doc/string/new.rdoc
  #
  def initialize(orig = (no_str = true; nil),
                encoding: (no_encoding = true; nil),
                capacity: (no_capacity = true; nil))
    return self if no_str && no_encoding && no_capacity

    # Pack the "argument was omitted" sentinels into one integer. This keeps the
    # builtin call at four arguments, within YJIT's limit for invokebuiltin.
    omitted = (no_str ? 1 : 0) | (no_encoding ? 2 : 0) | (no_capacity ? 4 : 0)

    Primitive.rb_str_init(orig, encoding, capacity, omitted)
  end
end
