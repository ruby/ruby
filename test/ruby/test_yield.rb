require 'test/unit'

class TestRubyYield < Test::Unit::TestCase

  def test_ary_each
    ary = [1]
    ary.each {|a, b, c, d| assert_equal [1,nil,nil,nil], [a,b,c,d] }
    ary.each {|a, b, c| assert_equal [1,nil,nil], [a,b,c] }
    ary.each {|a, b| assert_equal [1,nil], [a,b] }
    ary.each {|a| assert_equal 1, a }
  end

  def test_hash_each
    h = {:a => 1}
    h.each do |k, v|
      assert_equal :a, k
      assert_equal 1, v
    end
    h.each do |kv|
      assert_equal [:a, 1], kv
    end
  end

  def test_yield_0
    assert_equal 1, iter0 { 1 }
    assert_equal 2, iter0 { 2 }
  end

  def iter0
    yield
  end

  def test_yield_1
    iter1([]) {|a, b| assert_equal [nil,nil], [a, b] }
    iter1([1]) {|a, b| assert_equal [1,nil], [a, b] }
    iter1([1, 2]) {|a, b| assert_equal [1,2], [a,b] }
    iter1([1, 2, 3]) {|a, b| assert_equal [1,2], [a,b] }

    iter1([]) {|a| assert_equal [], a }
    iter1([1]) {|a| assert_equal [1], a }
    iter1([1, 2]) {|a| assert_equal [1,2], a }
    iter1([1, 2, 3]) {|a| assert_equal [1,2,3], a }
  end

  def iter1(args)
    yield args
  end

  def test_yield2
    def iter2_1() yield 1, *[2, 3] end
    iter2_1 {|a, b, c| assert_equal [1,2,3], [a,b,c] }
    def iter2_2() yield 1, *[] end
    iter2_2 {|a, b, c| assert_equal [1,nil,nil], [a,b,c] }
    def iter2_3() yield 1, *[2] end
    iter2_3 {|a, b, c| assert_equal [1,2,nil], [a,b,c] }
  end

  def test_yield_nested
    [[1, [2, 3]]].each {|a, (b, c)|
      assert_equal [1,2,3], [a,b,c]
    }
    [[1, [2, 3]]].map {|a, (b, c)|
      assert_equal [1,2,3], [a,b,c]
    }
  end

end
