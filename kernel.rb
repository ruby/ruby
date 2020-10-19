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
    Primitive.attr! 'inline'
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
    Primitive.attr! 'inline'
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
  #       then {|url| open(url).read }.
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
  def then
    unless Primitive.block_given_p
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
  #  Good usage for +then+ is value piping in method chains:
  #
  #     require 'open-uri'
  #     require 'json'
  #
  #     construct_url(arguments).
  #       then {|url| open(url).read }.
  #       then {|response| JSON.parse(response) }
  #
  def yield_self
    unless Primitive.block_given_p
      return Primitive.cexpr! 'SIZED_ENUMERATOR(self, 0, 0, rb_obj_size)'
    end
    yield(self)
  end

  #
  # call-seq:
  #   obj.deep_freeze
  #
  # Freeze all traversal objects.
  #
  def deep_freeze skip_shareable: false
    Primitive.obj_deep_freeze skip_shareable
  end

  module_function

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
    Primitive.rb_f_float(arg, exception)
  end
end
