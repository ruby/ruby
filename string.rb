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

    Primitive.rb_str_init(orig, no_str, encoding, no_encoding, capacity, no_capacity)
  end
end
