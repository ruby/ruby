# frozen_string_literal: true
require_relative 'xref_test_case'

class TestRDocRequire < XrefTestCase

  def setup
    super

    @req = RDoc::Require.new 'foo', 'comment'
  end

  def test_initialize
    assert_equal 'foo', @req.name

    RDoc::Require.new '"foo"', ''
    assert_equal 'foo', @req.name

    RDoc::Require.new '\'foo\'', ''
    assert_equal 'foo', @req.name

    RDoc::Require.new '|foo|', ''
    assert_equal 'foo', @req.name, 'for fortran?'
  end

end
