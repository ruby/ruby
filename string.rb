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

  #  call-seq:
  #    String.new(string = ''.encode(Encoding::ASCII_8BIT) , **options) -> new_string
  #
  #  Returns a new \String object containing the given +string+.
  #
  #  The +options+ are optional keyword options (see below).
  #
  #  With no argument given and keyword +encoding+ also not given,
  #  returns an empty string with the Encoding <tt>ASCII-8BIT</tt>:
  #
  #    s = String.new # => ""
  #    s.encoding     # => #<Encoding:ASCII-8BIT>
  #
  #  With argument +string+ given and keyword option +encoding+ not given,
  #  returns a new string with the same encoding as +string+:
  #
  #    s0 = 'foo'.encode(Encoding::UTF_16)
  #    s1 = String.new(s0)
  #    s1.encoding # => #<Encoding:UTF-16 (dummy)>
  #
  #  (Unlike \String.new,
  #  a {string literal}[rdoc-ref:syntax/literals.rdoc@String+Literals] like <tt>''</tt> or a
  #  {here document literal}[rdoc-ref:syntax/literals.rdoc@Here+Document+Literals]
  #  always has {script encoding}[rdoc-ref:encodings.rdoc@Script+Encoding].)
  #
  #  With keyword option +encoding+ given,
  #  returns a string with the specified encoding;
  #  the +encoding+ may be an Encoding object, an encoding name,
  #  or an encoding name alias:
  #
  #    String.new(encoding: Encoding::US_ASCII).encoding        # => #<Encoding:US-ASCII>
  #    String.new('', encoding: Encoding::US_ASCII).encoding    # => #<Encoding:US-ASCII>
  #    String.new('foo', encoding: Encoding::US_ASCII).encoding # => #<Encoding:US-ASCII>
  #    String.new('foo', encoding: 'US-ASCII').encoding         # => #<Encoding:US-ASCII>
  #    String.new('foo', encoding: 'ASCII').encoding            # => #<Encoding:US-ASCII>
  #
  #  The given encoding need not be valid for the string's content,
  #  and its validity is not checked:
  #
  #    s = String.new('こんにちは', encoding: 'ascii')
  #    s.valid_encoding? # => false
  #
  #  But the given +encoding+ itself is checked:
  #
  #    String.new('foo', encoding: 'bar') # Raises ArgumentError.
  #
  #  With keyword option +capacity+ given,
  #  the given value is advisory only,
  #  and may or may not set the size of the internal buffer,
  #  which may in turn affect performance:
  #
  #    String.new('foo', capacity: 1)    # Buffer size is at least 4 (includes terminal null byte).
  #    String.new('foo', capacity: 4096) # Buffer size is at least 4;
  #                                      # may be equal to, greater than, or less than 4096.
  def initialize(string = (string_unset = true), encoding: (encoding_unset = true), capacity: 0)
    # Avoid C primitive with more than 6 arguments as YJIT can't optimize them
    if string_unset
      Primitive.rb_str_new_enc_capa(encoding, encoding_unset, capacity)
    else
      Primitive.rb_str_init(string, encoding, encoding_unset, capacity)
    end
  end
end
