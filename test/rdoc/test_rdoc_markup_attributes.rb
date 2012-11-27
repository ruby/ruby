require 'rdoc/test_case'

class TestRDocMarkupAttributes < RDoc::TestCase

  def setup
    super

    @as = RDoc::Markup::Attributes.new
  end

  def test_bitmap_for
    assert_equal 2, @as.bitmap_for('two')
    assert_equal 2, @as.bitmap_for('two')
    assert_equal 4, @as.bitmap_for('three')
  end

  def test_as_string
    @as.bitmap_for 'two'
    @as.bitmap_for 'three'

    assert_equal 'none',          @as.as_string(0)
    assert_equal '_SPECIAL_',     @as.as_string(1)
    assert_equal 'two',           @as.as_string(2)
    assert_equal '_SPECIAL_,two', @as.as_string(3)
  end

  def test_each_name_of
    @as.bitmap_for 'two'
    @as.bitmap_for 'three'

    assert_equal %w[],          @as.each_name_of(0).to_a
    assert_equal %w[],          @as.each_name_of(1).to_a
    assert_equal %w[two],       @as.each_name_of(2).to_a
    assert_equal %w[three],     @as.each_name_of(4).to_a
    assert_equal %w[two three], @as.each_name_of(6).to_a
  end

end

