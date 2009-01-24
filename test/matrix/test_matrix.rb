require 'test/unit'
require 'matrix'

class TestMatrix < Test::Unit::TestCase
  def setup
    @m1 = Matrix[[1,2,3], [4,5,6]]
    @m2 = Matrix[[1,2,3], [4,5,6]]
    @m3 = @m1.clone
    @m4 = Matrix[[1,0, 2.0, 3.0], [4.0, 5.0, 6.0]]
    @n1 = Matrix[[2,3,4], [5,6,7]]
  end

  def test_identity
    assert_same @m1, @m1
    assert_not_same @m1, @m2
    assert_not_same @m1, @m3
    assert_not_same @m1, @m4
    assert_not_same @m1, @n1
  end

  def test_equality
    assert_equal @m1, @m1
    assert_equal @m1, @m2
    assert_equal @m1, @m3
    assert_not_equal @m1, @m4
    assert_not_equal @m1, @n1
  end

  def test_hash_equality
    assert @m1.eql?(@m1)
    assert @m1.eql?(@m2)
    assert @m1.eql?(@m3)
    assert !@m1.eql?(@m4)
    assert !@m1.eql?(@n1)

    hash = { @m1 => :value }
    assert hash.key?(@m1)
    assert hash.key?(@m2)
    assert hash.key?(@m3)
    assert !hash.key?(@m4)
    assert !hash.key?(@n1)
  end
end
