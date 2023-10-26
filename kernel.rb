module Kernel
  #
  #  call-seq:
  #     obj.class    -> class
  #
  #  Returns the class of <i>obj</i>. This method must always be called
  #  with an explicit receiver, as #class is also a reserved word in
  #  Ruby.
  #
  #     1.class      #=> Integer
  #     self.class   #=> Object
  #--
  # Equivalent to \c Object\#class in Ruby.
  #
  # Returns the class of \c obj, skipping singleton classes or module inclusions.
  #++
  #
  def class
    Primitive.attr! :leaf
    Primitive.cexpr! 'rb_obj_class(self)'
  end

  #
  #  call-seq:
  #     obj.clone(freeze: nil) -> an_object
  #
  #  Produces a shallow copy of <i>obj</i>---the instance variables of
  #  <i>obj</i> are copied, but not the objects they reference.
  #  #clone copies the frozen value state of <i>obj</i>, unless the
  #  +:freeze+ keyword argument is given with a false or true value.
  #  See also the discussion under Object#dup.
  #
  #     class Klass
  #        attr_accessor :str
  #     end
  #     s1 = Klass.new      #=> #<Klass:0x401b3a38>
  #     s1.str = "Hello"    #=> "Hello"
  #     s2 = s1.clone       #=> #<Klass:0x401b3998 @str="Hello">
  #     s2.str[1,4] = "i"   #=> "i"
  #     s1.inspect          #=> "#<Klass:0x401b3a38 @str=\"Hi\">"
  #     s2.inspect          #=> "#<Klass:0x401b3998 @str=\"Hi\">"
  #
  #  This method may have class-specific behavior.  If so, that
  #  behavior will be documented under the #+initialize_copy+ method of
  #  the class.
  #
  def clone(freeze: nil)
    Primitive.rb_obj_clone2(freeze)
  end

  #
  #  call-seq:
  #     obj.frozen?    -> true or false
  #
  #  Returns the freeze status of <i>obj</i>.
  #
  #     a = [ "a", "b", "c" ]
  #     a.freeze    #=> ["a", "b", "c"]
  #     a.frozen?   #=> true
  #--
  # Determines if the object is frozen. Equivalent to \c Object\#frozen? in Ruby.
  # \param[in] obj  the object to be determines
  # \retval Qtrue if frozen
  # \retval Qfalse if not frozen
  #++
  #
  def frozen?
    Primitive.attr! :leaf
    Primitive.cexpr! 'rb_obj_frozen_p(self)'
  end

  #
  #  call-seq:
  #     obj.tap {|x| block }    -> obj
  #
  #  Yields self to the block, and then returns self.
  #  The primary purpose of this method is to "tap into" a method chain,
  #  in order to perform operations on intermediate results within the chain.
  #
  #     (1..10)                  .tap {|x| puts "original: #{x}" }
  #       .to_a                  .tap {|x| puts "array:    #{x}" }
  #       .select {|x| x.even? } .tap {|x| puts "evens:    #{x}" }
  #       .map {|x| x*x }        .tap {|x| puts "squares:  #{x}" }
  #
  #--
  # \private
  #++
  #
  def tap
    yield(self)
    self
  end

  #
  #  call-seq:
  #     obj.then {|x| block }          -> an_object
  #
  #  Yields self to the block and returns the result of the block.
  #
  #     3.next.then {|x| x**x }.to_s             #=> "256"
  #
  #  Good usage for +then+ is value piping in method chains:
  #
  #     require 'open-uri'
  #     require 'json'
  #
  #     construct_url(arguments).
  #       then {|url| URI(url).read }.
  #       then {|response| JSON.parse(response) }
  #
  #  When called without block, the method returns +Enumerator+,
  #  which can be used, for example, for conditional
  #  circuit-breaking:
  #
  #     # meets condition, no-op
  #     1.then.detect(&:odd?)            # => 1
  #     # does not meet condition, drop value
  #     2.then.detect(&:odd?)            # => nil
  #
  #  Good usage for +then+ is value piping in method chains:
  #
  #     require 'open-uri'
  #     require 'json'
  #
  #     construct_url(arguments).
  #       then {|url| URI(url).read }.
  #       then {|response| JSON.parse(response) }
  #
  def then
    unless block_given?
      return Primitive.cexpr! 'SIZED_ENUMERATOR(self, 0, 0, rb_obj_size)'
    end
    yield(self)
  end

  #
  #  call-seq:
  #     obj.yield_self {|x| block }    -> an_object
  #
  #  Yields self to the block and returns the result of the block.
  #
  #     "my string".yield_self {|s| s.upcase }   #=> "MY STRING"
  #
  def yield_self
    unless block_given?
      return Primitive.cexpr! 'SIZED_ENUMERATOR(self, 0, 0, rb_obj_size)'
    end
    yield(self)
  end

  module_function

  # call-seq:
  #    loop { block }
  #    loop            -> an_enumerator
  #
  # Repeatedly executes the block.
  #
  # If no block is given, an enumerator is returned instead.
  #
  #    loop do
  #      print "Input: "
  #      line = gets
  #      break if !line or line =~ /^q/i
  #      # ...
  #    end
  #
  # StopIteration raised in the block breaks the loop.  In this case,
  # loop returns the "result" value stored in the exception.
  #
  #    enum = Enumerator.new { |y|
  #      y << "one"
  #      y << "two"
  #      :ok
  #    }
  #
  #    result = loop {
  #      puts enum.next
  #    } #=> :ok
  def loop
    unless block_given?
      return enum_for(:loop) { Float::INFINITY }
    end

    begin
      while true
        yield
      end
    rescue StopIteration => e
      e.result
    end
  end

  #
  #  call-seq:
  #     Float(arg, exception: true)    -> float or nil
  #
  #  Returns <i>arg</i> converted to a float. Numeric types are
  #  converted directly, and with exception to String and
  #  <code>nil</code> the rest are converted using
  #  <i>arg</i><code>.to_f</code>.  Converting a String with invalid
  #  characters will result in a ArgumentError.  Converting
  #  <code>nil</code> generates a TypeError.  Exceptions can be
  #  suppressed by passing <code>exception: false</code>.
  #
  #     Float(1)                 #=> 1.0
  #     Float("123.456")         #=> 123.456
  #     Float("123.0_badstring") #=> ArgumentError: invalid value for Float(): "123.0_badstring"
  #     Float(nil)               #=> TypeError: can't convert nil into Float
  #     Float("123.0_badstring", exception: false)  #=> nil
  #
  def Float(arg, exception: true)
    if Primitive.mandatory_only?
      Primitive.rb_f_float1(arg)
    else
      Primitive.rb_f_float(arg, exception)
    end
  end

  # call-seq:
  #   Integer(object, base = 0, exception: true) -> integer or nil
  #
  # Returns an integer converted from +object+.
  #
  # Tries to convert +object+ to an integer
  # using +to_int+ first and +to_i+ second;
  # see below for exceptions.
  #
  # With a non-zero +base+, +object+ must be a string or convertible
  # to a string.
  #
  # ==== numeric objects
  #
  # With integer argument +object+ given, returns +object+:
  #
  #   Integer(1)                # => 1
  #   Integer(-1)               # => -1
  #
  # With floating-point argument +object+ given,
  # returns +object+ truncated to an integer:
  #
  #   Integer(1.9)              # => 1  # Rounds toward zero.
  #   Integer(-1.9)             # => -1 # Rounds toward zero.
  #
  # ==== string objects
  #
  # With string argument +object+ and zero +base+ given,
  # returns +object+ converted to an integer in base 10:
  #
  #   Integer('100')    # => 100
  #   Integer('-100')   # => -100
  #
  # With +base+ zero, string +object+ may contain leading characters
  # to specify the actual base (radix indicator):
  #
  #   Integer('0100')  # => 64  # Leading '0' specifies base 8.
  #   Integer('0b100') # => 4   # Leading '0b', specifies base 2.
  #   Integer('0x100') # => 256 # Leading '0x' specifies base 16.
  #
  # With a positive +base+ (in range 2..36) given, returns +object+
  # converted to an integer in the given base:
  #
  #   Integer('100', 2)   # => 4
  #   Integer('100', 8)   # => 64
  #   Integer('-100', 16) # => -256
  #
  # With a negative +base+ (in range -36..-2) given, returns +object+
  # converted to an integer in the radix indicator if exists or
  # +-base+:
  #
  #   Integer('0x100', -2)   # => 256
  #   Integer('100', -2)     # => 4
  #   Integer('0b100', -8)   # => 4
  #   Integer('100', -8)     # => 64
  #   Integer('0o100', -10)  # => 64
  #   Integer('100', -10)    # => 100
  #
  # +base+ -1 is equal the -10 case.
  #
  # When converting strings, surrounding whitespace and embedded underscores
  # are allowed and ignored:
  #
  #   Integer(' 100 ')      # => 100
  #   Integer('-1_0_0', 16) # => -256
  #
  # ==== other classes
  #
  # Examples with +object+ of various other classes:
  #
  #   Integer(Rational(9, 10)) # => 0  # Rounds toward zero.
  #   Integer(Complex(2, 0))   # => 2  # Imaginary part must be zero.
  #   Integer(Time.now)        # => 1650974042
  #
  # ==== keywords
  #
  # With optional keyword argument +exception+ given as +true+ (the default):
  #
  # - Raises TypeError if +object+ does not respond to +to_int+ or +to_i+.
  # - Raises TypeError if +object+ is +nil+.
  # - Raise ArgumentError if +object+ is an invalid string.
  #
  # With +exception+ given as +false+, an exception of any kind is suppressed
  # and +nil+ is returned.

  def Integer(arg, base = 0, exception: true)
    if Primitive.mandatory_only?
      Primitive.rb_f_integer1(arg)
    else
      Primitive.rb_f_integer(arg, base, exception);
    end
  end
end
