require_relative "test_helper"

require "bigdecimal"

class MathTest < StdlibTest
  target Math
  using hook.refinement

  %w(
    acos
    acosh
    asin
    asinh
    atan
    atanh
    cbrt
    cos
    cosh
    erf
    erfc
    exp
    gamma
    lgamma
    log10
    log2
    sin
    sinh
    sqrt
    tan
    tanh
  ).each do |method_name|
    define_method("test_#{method_name}") do
      Math.public_send(method_name, 1)
      Math.public_send(method_name, 1.0)
      Math.public_send(method_name, 1r)
      Math.public_send(method_name, BigDecimal("1"))
    end
  end

  %w(
    atan2
    hypot
    ldexp
  ).each do |method_name|
    define_method("test_#{method_name}") do
      Math.public_send(method_name, 1, 1.0)
      Math.public_send(method_name, 1.0, 1r)
      Math.public_send(method_name, 1r, BigDecimal("1"))
      Math.public_send(method_name, BigDecimal("1"), 1)
    end
  end

  def test_log
    Math.log(1)
    Math.log(1.0)
    Math.log(1r)
    Math.log(BigDecimal("1"))
    Math.log(1, 1.0)
    Math.log(1.0, 1r)
    Math.log(1r, BigDecimal("1"))
    Math.log(BigDecimal("1"), 1)
  end
end
