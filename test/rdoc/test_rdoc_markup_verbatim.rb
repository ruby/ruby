require 'rdoc/test_case'

class TestRDocMarkupVerbatim < RDoc::TestCase

  def test_equals2
    v1 = verb('1 + 1')
    v2 = verb('1 + 1')
    v3 = verb('1 + 2')
    v4 = verb('1 + 1')
    v4.format = :ruby

    assert_equal v1, v2

    refute_equal v1, v3
    refute_equal v1, v4
  end

  def test_ruby_eh
    verbatim = RDoc::Markup::Verbatim.new

    refute verbatim.ruby?

    verbatim.format = :ruby

    assert verbatim.ruby?
  end

end

