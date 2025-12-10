# A \Float object stores a real number
# using the native architecture's double-precision floating-point representation.
#
# == \Float Imprecisions
#
# Some real numbers can be represented precisely as \Float objects:
#
#   37.5    # => 37.5
#   98.75   # => 98.75
#   12.3125 # => 12.3125
#
# Others cannot; among these are the transcendental numbers, including:
#
# - Pi, <i>π</i>: in mathematics, a number of infinite precision:
#   3.1415926535897932384626433... (to 25 places);
#   in Ruby, it is of limited precision (in this case, to 16 decimal places):
#
#     Math::PI # => 3.141592653589793
#
# - Euler's number, <i>e</i>: in mathematics, a number of infinite precision:
#   2.7182818284590452353602874... (to 25 places);
#   in Ruby, it is of limited precision (in this case, to 15 decimal places):
#
#     Math::E # => 2.718281828459045
#
# Some floating-point computations in Ruby give precise results:
#
#   1.0/2   # => 0.5
#   100.0/8 # => 12.5
#
# Others do not:
#
# - In mathematics, 2/3 as a decimal number is an infinitely-repeating decimal:
#   0.666... (forever);
#   in Ruby, +2.0/3+ is of limited precision (in this case, to 16 decimal places):
#
#     2.0/3 # => 0.6666666666666666
#
# - In mathematics, the square root of 2 is an irrational number of infinite precision:
#   1.4142135623730950488016887... (to 25 decimal places);
#   in Ruby, it is of limited precision (in this case, to 16 decimal places):
#
#     Math.sqrt(2.0) # => 1.4142135623730951
#
# - Even a simple computation can introduce imprecision:
#
#     x = 0.1 + 0.2 # => 0.30000000000000004
#     y = 0.3       # => 0.3
#     x == y        # => false
#
# See:
#
# - https://docs.oracle.com/cd/E19957-01/806-3568/ncg_goldberg.html
# - https://github.com/rdp/ruby_tutorials_core/wiki/Ruby-Talk-FAQ#-why-are-rubys-floats-imprecise
# - https://en.wikipedia.org/wiki/Floating_point#Accuracy_problems
#
# Note that precise storage and computation of rational numbers
# is possible using Rational objects.
#
# == Creating a \Float
#
# You can create a \Float object explicitly with:
#
# - A {floating-point literal}[rdoc-ref:syntax/literals.rdoc@Float+Literals].
#
# You can convert certain objects to Floats with:
#
# - Method #Float.
#
# == What's Here
#
# First, what's elsewhere. Class \Float:
#
# - Inherits from
#   {class Numeric}[rdoc-ref:Numeric@What-27s+Here]
#   and {class Object}[rdoc-ref:Object@What-27s+Here].
# - Includes {module Comparable}[rdoc-ref:Comparable@What-27s+Here].
#
# Here, class \Float provides methods for:
#
# - {Querying}[rdoc-ref:Float@Querying]
# - {Comparing}[rdoc-ref:Float@Comparing]
# - {Converting}[rdoc-ref:Float@Converting]
#
# === Querying
#
# - #finite?: Returns whether +self+ is finite.
# - #hash: Returns the integer hash code for +self+.
# - #infinite?: Returns whether +self+ is infinite.
# - #nan?: Returns whether +self+ is a NaN (not-a-number).
#
# === Comparing
#
# - #<: Returns whether +self+ is less than the given value.
# - #<=: Returns whether +self+ is less than or equal to the given value.
# - #<=>: Returns a number indicating whether +self+ is less than, equal
#   to, or greater than the given value.
# - #== (aliased as #=== and #eql?): Returns whether +self+ is equal to
#   the given value.
# - #>: Returns whether +self+ is greater than the given value.
# - #>=: Returns whether +self+ is greater than or equal to the given value.
#
# === Converting
#
# - #% (aliased as #modulo): Returns +self+ modulo the given value.
# - #*: Returns the product of +self+ and the given value.
# - #**: Returns the value of +self+ raised to the power of the given value.
# - #+: Returns the sum of +self+ and the given value.
# - #-: Returns the difference of +self+ and the given value.
# - #/: Returns the quotient of +self+ and the given value.
# - #ceil: Returns the smallest number greater than or equal to +self+.
# - #coerce: Returns a 2-element array containing the given value converted to a \Float
#   and +self+
# - #divmod: Returns a 2-element array containing the quotient and remainder
#   results of dividing +self+ by the given value.
# - #fdiv: Returns the \Float result of dividing +self+ by the given value.
# - #floor: Returns the greatest number smaller than or equal to +self+.
# - #next_float: Returns the next-larger representable \Float.
# - #prev_float: Returns the next-smaller representable \Float.
# - #quo: Returns the quotient from dividing +self+ by the given value.
# - #round: Returns +self+ rounded to the nearest value, to a given precision.
# - #to_i (aliased as #to_int): Returns +self+ truncated to an Integer.
# - #to_s (aliased as #inspect): Returns a string containing the place-value
#   representation of +self+ in the given radix.
# - #truncate: Returns +self+ truncated to a given precision.
#

 class Float; end
