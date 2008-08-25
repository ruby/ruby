require 'test/unit'

class TestComparable < Test::Unit::TestCase
  def setup
    @o = Object.new
    @o.extend(Comparable)
  end

  def test_equal
    def @o.<=>(x); 0; end
    assert_equal(true, @o == nil)
    def @o.<=>(x); 1; end
    assert_equal(false, @o == nil)
    def @o.<=>(x); raise; end
    assert_equal(false, @o == nil)
  end

  def test_gt
    def @o.<=>(x); 1; end
    assert_equal(true, @o > nil)
    def @o.<=>(x); 0; end
    assert_equal(false, @o > nil)
    def @o.<=>(x); -1; end
    assert_equal(false, @o > nil)
  end

  def test_ge
    def @o.<=>(x); 1; end
    assert_equal(true, @o >= nil)
    def @o.<=>(x); 0; end
    assert_equal(true, @o >= nil)
    def @o.<=>(x); -1; end
    assert_equal(false, @o >= nil)
  end

  def test_lt
    def @o.<=>(x); 1; end
    assert_equal(false, @o < nil)
    def @o.<=>(x); 0; end
    assert_equal(false, @o < nil)
    def @o.<=>(x); -1; end
    assert_equal(true, @o < nil)
  end

  def test_le
    def @o.<=>(x); 1; end
    assert_equal(false, @o <= nil)
    def @o.<=>(x); 0; end
    assert_equal(true, @o <= nil)
    def @o.<=>(x); -1; end
    assert_equal(true, @o <= nil)
  end

  def test_between
    def @o.<=>(x); 0 <=> x end
    assert_equal(false, @o.between?(1, 2))
    assert_equal(false, @o.between?(-2, -1))
    assert_equal(true, @o.between?(-1, 1))
    assert_equal(true, @o.between?(0, 0))
  end

  def test_err
    assert_raise(ArgumentError) { 1.0 < nil }
    assert_raise(ArgumentError) { 1.0 < Object.new }
  end
end
