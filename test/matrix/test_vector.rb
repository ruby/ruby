require 'test/unit'
require 'matrix'

class TestVector < Test::Unit::TestCase
  def setup
    @v1 = Vector[1,2,3]
    @v2 = Vector[1,2,3]
    @v3 = @v1.clone
    @v4 = Vector[1,0, 2.0, 3.0]
    @w1 = Vector[2,3,4]
  end

  def test_identity
    assert_same @v1, @v1
    assert_not_same @v1, @v2
    assert_not_same @v1, @v3
    assert_not_same @v1, @v4
    assert_not_same @v1, @w1
  end

  def test_equality
    assert_equal @v1, @v1
    assert_equal @v1, @v2
    assert_equal @v1, @v3
    assert_not_equal @v1, @v4
    assert_not_equal @v1, @w1
  end

  def test_hash_equality
    assert @v1.eql?(@v1)
    assert @v1.eql?(@v2)
    assert @v1.eql?(@v3)
    assert !@v1.eql?(@v4)
    assert !@v1.eql?(@w1)

    hash = { @v1 => :value }
    assert hash.key?(@v1)
    assert hash.key?(@v2)
    assert hash.key?(@v3)
    assert !hash.key?(@v4)
    assert !hash.key?(@w1)
  end
end
