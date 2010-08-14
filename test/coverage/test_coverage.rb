require "test/unit"
require "coverage"

class TestCoverage < Test::Unit::TestCase
  def test_result_without_start
    assert_raise(RuntimeError) {Coverage.result}
  end
  def test_result_with_nothing
    Coverage.start
    result = Coverage.result
    assert_kind_of(Hash, result)
    result.each do |key, val|
      assert_kind_of(String, key)
      assert_kind_of(Array, val)
    end
  end
end
