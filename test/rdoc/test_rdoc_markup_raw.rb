# frozen_string_literal: true
require 'minitest_helper'

class TestRDocMarkupRaw < RDoc::TestCase

  def setup
    super

    @p = @RM::Raw.new
  end

  def test_push
    @p.push 'hi', 'there'

    assert_equal @RM::Raw.new('hi', 'there'), @p
  end

  def test_pretty_print
    assert_equal '[raw: ]', mu_pp(@p)
  end

end

