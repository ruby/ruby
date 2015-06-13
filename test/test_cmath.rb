require 'test/unit'
require 'cmath'

class TestCMath < Test::Unit::TestCase
  def test_sqrt
    assert_equal CMath.sqrt(1i), CMath.sqrt(1.0i), '[ruby-core:31672]'
    assert_in_delta 1.272019649514069+0.7861513777574233i, CMath.sqrt(1+2i)
    assert_in_delta 3.0i, CMath.sqrt(-9)
    assert_equal Complex(0,2), CMath.sqrt(-4.0)
    assert_equal Complex(0,2), CMath.sqrt(-4)
    assert_equal Complex(0,2), CMath.sqrt(Rational(-4))
    assert_equal Complex(0,3), CMath.sqrt(-9.0)
    assert_equal Complex(0,3), CMath.sqrt(-9)
    assert_equal Complex(0,3), CMath.sqrt(Rational(-9))
  end

  def test_log
    assert_in_delta 0.8047189562170503+1.1071487177940904i, CMath.log(1+2i)
    assert_in_delta 0.7324867603589635+1.0077701926457874i, CMath.log(1+2i,3)
    assert_in_delta Math::PI*1i                           , CMath.log(-1)
    assert_in_delta 3.0                                   , CMath.log(8, 2)
    assert_in_delta 1.092840647090816-0.42078724841586035i, CMath.log(-8, -2)
  end

  def test_trigonometric_functions
    assert_in_delta CMath.sinh(2).i, CMath.sin(2i)
    assert_in_delta CMath.cosh(2),   CMath.cos(2i)
    assert_in_delta CMath.tanh(2).i, CMath.tan(2i)

    assert_in_delta CMath.sin(2).i, CMath.sinh(2i)
    assert_in_delta CMath.cos(2),   CMath.cosh(2i)
    assert_in_delta CMath.tan(2).i, CMath.tanh(2i)

    assert_in_delta 1+1i, CMath.sin(CMath.asin(1+1i))
    assert_in_delta 1+1i, CMath.cos(CMath.acos(1+1i))
    assert_in_delta 1+1i, CMath.tan(CMath.atan(1+1i))

    assert_in_delta 1+1i, CMath.sinh(CMath.asinh(1+1i))
    assert_in_delta 1+1i, CMath.cosh(CMath.acosh(1+1i))
    assert_in_delta 1+1i, CMath.tanh(CMath.atanh(1+1i))

    assert_in_delta 3.165778513216168+1.959601041421606i    , CMath.sin(1+2i)
    assert_in_delta 2.0327230070196656-3.0518977991517997i  , CMath.cos(1+2i)
    assert_in_delta 0.033812826079896774+1.0147936161466338i, CMath.tan(1+2i)
    assert_in_delta -0.4890562590412937+1.4031192506220405i , CMath.sinh(1+2i)
    assert_in_delta -0.64214812471552+1.0686074213827783i   , CMath.cosh(1+2i)
    assert_in_delta 1.16673625724092-0.2434582011857252i    , CMath.tanh(1+2i)
    assert_in_delta 0.4270785863924755+1.5285709194809978i  , CMath.asin(1+2i)
    assert_in_delta 1.1437177404024204-1.528570919480998i   , CMath.acos(1+2i)
    assert_in_delta 1.3389725222944935+0.4023594781085251i  , CMath.atan(1+2i)
    assert_in_delta 1.4693517443681852+1.0634400235777521i  , CMath.asinh(1+2i)
    assert_in_delta 1.528570919480998+1.1437177404024204i   , CMath.acosh(1+2i)
    assert_in_delta 0.17328679513998635+1.1780972450961724i , CMath.atanh(1+2i)
  end

  def test_functions
    assert_in_delta -1.1312043837568135+2.4717266720048188i, CMath.exp(1+2i)
    assert_in_delta -1                                     , CMath.exp(Math::PI.i)
    assert_in_delta 1.1609640474436813+1.5972779646881088i , CMath.log2(1+2i)
    assert_in_delta 0.3494850021680094+0.480828578784234i  , CMath.log10(1+2i)
    assert_in_delta 1.3389725222944935+0.4023594781085251i , CMath.atan2(1+2i,1)
  end

  def test_error_handling
    assert_raise_with_message(TypeError, "Numeric Number required") { CMath.acos("2") }
    assert_raise_with_message(TypeError, "Numeric Number required") { CMath.log("2") }
    assert_raise(ArgumentError) { CMath.log(2, "2") }
    assert_raise(NoMethodError) { CMath.log(2, 2i) }
    assert_raise(RangeError) { CMath.hypot(2i, 2i) }
  end

  def test_cbrt_returns_principal_value_of_cube_root
    assert_equal (-8)**(1.0/3), CMath.cbrt(-8), '#3676'
  end
end
