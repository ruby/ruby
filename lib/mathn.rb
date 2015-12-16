# frozen_string_literal: false
#--
# $Release Version: 0.5 $
# $Revision: 1.1.1.1.4.1 $

##
# = mathn
#
# mathn serves to make mathematical operations more precise in Ruby
# and to integrate other mathematical standard libraries.
#
# Without mathn:
#
#   3 / 2 => 1 # Integer
#
# With mathn:
#
#   3 / 2 => 3/2 # Rational
#
# mathn keeps value in exact terms.
#
# Without mathn:
#
#   20 / 9 * 3 * 14 / 7 * 3 / 2 # => 18
#
# With mathn:
#
#   20 / 9 * 3 * 14 / 7 * 3 / 2 # => 20
#
#
# When you require 'mathn', the libraries for Prime, CMath, Matrix and Vector
# are also loaded.
#
# == Copyright
#
# Author: Keiju ISHITSUKA (SHL Japan Inc.)
#--
# class Numeric follows to make this documentation findable in a reasonable
# location

warn('lib/mathn.rb is deprecated') if $VERBOSE

class Numeric; end

require "cmath.rb"
require "matrix.rb"
require "prime.rb"

require "mathn/rational"
require "mathn/complex"

unless defined?(Math.exp!)
  Object.instance_eval{remove_const :Math}
  Math = CMath # :nodoc:
end

##
# When mathn is required, Fixnum's division is enhanced to
# return more precise values from mathematical expressions.
#
#   2/3*3  # => 0
#   require 'mathn'
#   2/3*3  # => 2

class Fixnum
  remove_method :/

  ##
  # +/+ defines the Rational division for Fixnum.
  #
  #   1/3  # => (1/3)

  alias / quo
end

##
# When mathn is required Bignum's division is enhanced to
# return more precise values from mathematical expressions.
#
#   (2**72) / ((2**70) * 3)  # => 4/3

class Bignum
  remove_method :/

  ##
  # +/+ defines the Rational division for Bignum.
  #
  #   (2**72) / ((2**70) * 3)  # => 4/3

  alias / quo
end

##
# When mathn is required, the Math module changes as follows:
#
# Standard Math module behaviour:
#   Math.sqrt(4/9)     # => 0.0
#   Math.sqrt(4.0/9.0) # => 0.666666666666667
#   Math.sqrt(- 4/9)   # => Errno::EDOM: Numerical argument out of domain - sqrt
#
# After require 'mathn', this is changed to:
#
#   require 'mathn'
#   Math.sqrt(4/9)      # => 2/3
#   Math.sqrt(4.0/9.0)  # => 0.666666666666667
#   Math.sqrt(- 4/9)    # => Complex(0, 2/3)

module Math
  remove_method(:sqrt)

  ##
  # Computes the square root of +a+.  It makes use of Complex and
  # Rational to have no rounding errors if possible.
  #
  #   Math.sqrt(4/9)      # => 2/3
  #   Math.sqrt(- 4/9)    # => Complex(0, 2/3)
  #   Math.sqrt(4.0/9.0)  # => 0.666666666666667

  def sqrt(a)
    if a.kind_of?(Complex)
      abs = sqrt(a.real*a.real + a.imag*a.imag)
      x = sqrt((a.real + abs)/Rational(2))
      y = sqrt((-a.real + abs)/Rational(2))
      if a.imag >= 0
        Complex(x, y)
      else
        Complex(x, -y)
      end
    elsif a.respond_to?(:nan?) and a.nan?
      a
    elsif a >= 0
      rsqrt(a)
    else
      Complex(0,rsqrt(-a))
    end
  end

  ##
  # Compute square root of a non negative number. This method is
  # internally used by +Math.sqrt+.

  def rsqrt(a)
    if a.kind_of?(Float)
      sqrt!(a)
    elsif a.kind_of?(Rational)
      rsqrt(a.numerator)/rsqrt(a.denominator)
    else
      src = a
      max = 2 ** 32
      byte_a = [src & 0xffffffff]
      # ruby's bug
      while (src >= max) and (src >>= 32)
        byte_a.unshift src & 0xffffffff
      end

      answer = 0
      main = 0
      side = 0
      for elm in byte_a
        main = (main << 32) + elm
        side <<= 16
        if answer != 0
          if main * 4  < side * side
            applo = main.div(side)
          else
            applo = ((sqrt!(side * side + 4 * main) - side)/2.0).to_i + 1
          end
        else
          applo = sqrt!(main).to_i + 1
        end

        while (x = (side + applo) * applo) > main
          applo -= 1
        end
        main -= x
        answer = (answer << 16) + applo
        side += applo * 2
      end
      if main == 0
        answer
      else
        sqrt!(a)
      end
    end
  end

  class << self
    remove_method(:sqrt)
  end
  module_function :sqrt
  module_function :rsqrt
end
