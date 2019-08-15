#!/usr/local/bin/ruby
# frozen_string_literal: false

#
# nlsolve.rb
# An example for solving nonlinear algebraic equation system.
#

require "bigdecimal"
require "bigdecimal/newton"
include Newton

class Function # :nodoc: all
  def initialize()
    @zero = BigDecimal("0.0")
    @one  = BigDecimal("1.0")
    @two  = BigDecimal("2.0")
    @ten  = BigDecimal("10.0")
    @eps  = BigDecimal("1.0e-16")
  end
  def zero;@zero;end
  def one ;@one ;end
  def two ;@two ;end
  def ten ;@ten ;end
  def eps ;@eps ;end
  def values(x) # <= defines functions solved
    f = []
    f1 = x[0]*x[0] + x[1]*x[1] - @two # f1 = x**2 + y**2 - 2 => 0
    f2 = x[0] - x[1]                  # f2 = x    - y        => 0
    f <<= f1
    f <<= f2
    f
  end
end

f = BigDecimal.limit(100)
f = Function.new
x = [f.zero,f.zero]      # Initial values
n = nlsolve(f,x)
p x
