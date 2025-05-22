# frozen_string_literal: true
require_relative 'helper'

class RDocMarkupIncludeTest < RDoc::TestCase

  def setup
    super

    @include = @RM::Include.new 'file', [Dir.tmpdir]
  end

  def test_equals2
    assert_equal @include, @RM::Include.new('file', [Dir.tmpdir])
    refute_equal @include, @RM::Include.new('file', %w[.])
    refute_equal @include, @RM::Include.new('other', [Dir.tmpdir])
    refute_equal @include, Object.new
  end

end
