require 'test/unit'
require '-test-/hash'

class TestHash < Test::Unit::TestCase
  class TestDelete < Test::Unit::TestCase
    def test_delete
      hash = Bug::Hash.new
      hash[1] = 2
      called = false
      assert_equal 1, hash.size
      assert_equal true, hash.delete(1) {called = true}
      assert_equal false, called, "block called"
      assert_equal 0, hash.size
      assert_equal false, hash.delete(1) {called = true}
      assert_equal false, called, "block called"
      assert_equal 0, hash.size
    end
  end
end
