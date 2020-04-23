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
  #     Integer(arg, base=0, exception: true)    -> integer or nil
  #
  #  Converts <i>arg</i> to an Integer.
  #  Numeric types are converted directly (with floating point numbers
  #  being truncated).  <i>base</i> (0, or between 2 and 36) is a base for
  #  integer string representation.  If <i>arg</i> is a String,
  #  when <i>base</i> is omitted or equals zero, radix indicators
  #  (<code>0</code>, <code>0b</code>, and <code>0x</code>) are honored.
  #  In any case, strings should be strictly conformed to numeric
  #  representation. This behavior is different from that of
  #  String#to_i.  Non string values will be converted by first
  #  trying <code>to_int</code>, then <code>to_i</code>.
  #
  #  Passing <code>nil</code> raises a TypeError, while passing a String that
  #  does not conform with numeric representation raises an ArgumentError.
  #  This behavior can be altered by passing <code>exception: false</code>,
  #  in this case a not convertible value will return <code>nil</code>.
  #
  #     Integer(123.999)    #=> 123
  #     Integer("0x1a")     #=> 26
  #     Integer(Time.new)   #=> 1204973019
  #     Integer("0930", 10) #=> 930
  #     Integer("111", 2)   #=> 7
  #     Integer(nil)        #=> TypeError: can't convert nil into Integer
  #     Integer("x")        #=> ArgumentError: invalid value for Integer(): "x"
  #
  #     Integer("x", exception: false)        #=> nil
  #
  #
  def Integer(arg, base = 0, exception: true)
    __builtin_rb_f_integer(arg, base, exception)
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
    __builtin_rb_f_float(arg, exception)
  end
end
