class String
  #  call-seq:
  #    valid_encoding? -> true or false
  #
  #  Returns whether +self+ is encoded correctly:
  #
  #    s = 'Straße'
  #    s.valid_encoding?                                 # => true
  #    s.encoding                                        # => #<Encoding:UTF-8>
  #    s.force_encoding(Encoding::ASCII).valid_encoding? # => false
  #
  #  Related: see {Querying}[rdoc-ref:String@Querying].
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
end
