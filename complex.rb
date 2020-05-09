module Kernel
  module_function
  #
  # call-seq:
  #    Complex(x[, y], exception: true)  ->  numeric or nil
  #
  # Returns x+i*y;
  #
  #    Complex(1, 2)    #=> (1+2i)
  #    Complex('1+2i')  #=> (1+2i)
  #    Complex(nil)     #=> TypeError
  #    Complex(1, nil)  #=> TypeError
  #
  #    Complex(1, nil, exception: false)  #=> nil
  #    Complex('1+2', exception: false)   #=> nil
  #
  # Syntax of string form:
  #
  #   string form = extra spaces , complex , extra spaces ;
  #   complex = real part | [ sign ] , imaginary part
  #           | real part , sign , imaginary part
  #           | rational , "@" , rational ;
  #   real part = rational ;
  #   imaginary part = imaginary unit | unsigned rational , imaginary unit ;
  #   rational = [ sign ] , unsigned rational ;
  #   unsigned rational = numerator | numerator , "/" , denominator ;
  #   numerator = integer part | fractional part | integer part , fractional part ;
  #   denominator = digits ;
  #   integer part = digits ;
  #   fractional part = "." , digits , [ ( "e" | "E" ) , [ sign ] , digits ] ;
  #   imaginary unit = "i" | "I" | "j" | "J" ;
  #   sign = "-" | "+" ;
  #   digits = digit , { digit | "_" , digit };
  #   digit = "0" | "1" | "2" | "3" | "4" | "5" | "6" | "7" | "8" | "9" ;
  #   extra spaces = ? \s* ? ;
  #
  # See String#to_c.
  #
  def Complex(*args, exception: true)
    __builtin_nucomp_f_complex(args, exception)
  end
end
