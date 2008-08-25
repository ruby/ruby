require 'test/unit'

class TestPrecision < Test::Unit::TestCase
  def test_prec_i
    assert_same(1, 1.0.prec(Integer))
    assert_same(1, 1.0.prec_i)
    assert_same(1, Integer.induced_from(1.0))
  end

  def test_prec_f
    assert_equal(1.0, 1.prec(Float))
    assert_equal(1.0, 1.prec_f)
    assert_equal(1.0, Float.induced_from(1))
  end

  def test_induced_from
    m = Module.new
    m.instance_eval { include(Precision) }
    assert_raise(TypeError) { m.induced_from(0) }
  end
end
