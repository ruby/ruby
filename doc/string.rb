class String
  # call-seq:
  #   String.new(string = '') -> new_string
  #   String.new(string = '', encoding: encoding) -> new_string
  #   String.new(string = '', capacity: size) -> new_string
  #
  # Returns a new \String that is a copy of +string+.
  #
  # With no arguments, returns the empty string with the Encoding <tt>ASCII-8BIT</tt>:
  #   s = String.new
  #   s # => ""
  #   s.encoding # => #<Encoding:ASCII-8BIT>
  #
  # With the single \String argument +string+, returns a copy of +string+
  # with the same encoding as +string+:
  #   s = String.new('Que veut dire ça?')
  #   s # => "Que veut dire ça?"
  #   s.encoding # => #<Encoding:UTF-8>
  #
  # Literal strings like <tt>""</tt> or here-documents always use
  # Encoding@Script+encoding, unlike String.new.
  #
  # With keyword +encoding+, returns a copy of +str+
  # with the specified encoding:
  #   s = String.new(encoding: 'ASCII')
  #   s.encoding # => #<Encoding:US-ASCII>
  #   s = String.new('foo', encoding: 'ASCII')
  #   s.encoding # => #<Encoding:US-ASCII>
  #
  # Note that these are equivalent:
  #   s0 = String.new('foo', encoding: 'ASCII')
  #   s1 = 'foo'.force_encoding('ASCII')
  #   s0.encoding == s1.encoding # => true
  #
  # With keyword +capacity+, returns a copy of +str+;
  # the given +capacity+ may set the size of the internal buffer,
  # which may affect performance:
  #   String.new(capacity: 1) # => ""
  #   String.new(capacity: 4096) # => ""
  #
  # The +string+, +encoding+, and +capacity+ arguments may all be used together:
  #
  #   String.new('hello', encoding: 'UTF-8', capacity: 25)
  #
  def initialize(str = '', encoding: nil, capacity: nil)
    Primitive.rb_str_init(str, encoding, capacity)
  end
end
