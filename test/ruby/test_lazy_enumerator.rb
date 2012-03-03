require 'test/unit'

class TestLazyEnumerator < Test::Unit::TestCase

  def test_initialize
    assert_equal([1, 2, 3], [1, 2, 3].lazy.to_a)
    assert_equal([1, 2, 3], Enumerable::Lazy.new([1, 2, 3]).to_a)
  end

  def test_select
    a = [1, 2, 3, 4, 5, 6]
    assert_equal([4, 5, 6], a.lazy.select { |x| x > 3 }.to_a)
  end

  def test_map
    a = [1, 2, 3]
    assert_equal([2, 4, 6], a.lazy.map { |x| x * 2 }.to_a)
  end

  def test_reject
    a = [1, 2, 3, 4, 5, 6]
    assert_equal([1, 2, 3], a.lazy.reject { |x| x > 3 }.to_a)
  end

  def test_grep
    a = ['a', 'b', 'c', 'd', 'f']
    assert_equal(['c'], a.lazy.grep(/c/).to_a)
  end

end
