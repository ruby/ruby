require File.expand_path '../xref_test_case', __FILE__

class TestRDocInclude < XrefTestCase

  def setup
    super

    @inc = RDoc::Include.new 'M1', 'comment'
  end

  def test_module
    assert_equal @m1, @inc.module
    assert_equal 'Unknown', RDoc::Include.new('Unknown', 'comment').module
  end

end

