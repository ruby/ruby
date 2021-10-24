require 'test/unit'
require '-test-/enumerator_kw'

class TestEnumeratorKw < Test::Unit::TestCase
  def test_enumerator_kw
    o = Object.new
    o.extend Bug::EnumeratorKw
    assert_equal([nil, [], {:a=>1}, o], o.m(a: 1) { |*a| a })
    assert_equal([nil, [[], {:a=>1}, o], nil, o], o.m(a: 1).each { |*a| a })
  end
end
