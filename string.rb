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

  # :nodoc:
  def self._new(orig = (no_str = true; nil),
                encoding: (no_encoding = true; nil),
                capacity: (no_capacity = true; nil))

    Primitive.rb_str_s_new(orig, no_str, encoding, no_encoding, capacity, no_capacity)
  end
  private_class_method :_new

  def initialize(orig = (no_str = true; nil),
                encoding: (no_encoding = true; nil),
                capacity: (no_capacity = true; nil))
    Primitive.rb_str_init(orig, no_str, encoding, no_encoding, capacity, no_capacity)
  end

  #  call-seq:
  #    String.new(string = ''.encode(Encoding::ASCII_8BIT), **options) -> new_string
  #
  #  :include: doc/string/new.rdoc
  #
  def self.new(...)
    # If the receiver isn't a String, jbb
    if Primitive.mandatory_only?
      if String.equal?(self)
        Primitive.rb_str_s_new_empty
      else
        super
      end
    else
      if String.equal?(self)
        _new(...)
      else
        super
      end
    end
  end
end
