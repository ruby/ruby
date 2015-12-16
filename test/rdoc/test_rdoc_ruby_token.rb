# frozen_string_literal: false
require 'rdoc/test_case'

class TestRDocRubyToken < RDoc::TestCase

  def test_Token_text
    token = RDoc::RubyToken::Token.new 0, 0, 0, 'text'

    assert_equal 'text', token.text
  end

  def test_TkOp_name
    token = RDoc::RubyToken::TkOp.new 0, 0, 0, '&'

    assert_equal '&', token.text
    assert_equal '&', token.name
  end

end

