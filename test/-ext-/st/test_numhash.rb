require 'test/unit'
require "-test-/st/numhash"

class Bug::StNumHash
  class Test_NumHash < Test::Unit::TestCase
    def setup
      @tbl = Bug::StNumHash.new
      5.times {|i| @tbl[i] = i}
    end

    def test_check
      keys = []
      @tbl.each do |k, v, t|
        keys << k
        t[5] = 5 if k == 3
        true
      end
      assert_equal([*0..5], keys)
    end

    def test_update
      assert_equal(true, @tbl.update(0) {@tbl[5] = :x})
      assert_equal(:x, @tbl[0])
      assert_equal(:x, @tbl[5])
    end
  end
end
