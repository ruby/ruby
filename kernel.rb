module Kernel
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
    __builtin_rb_obj_clone2(freeze)
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
    __builtin_rb_f_float(arg, exception)
  end
end
