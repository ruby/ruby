# frozen_string_literal: false
require_relative 'base'
require 'tempfile'

class TestMkmf
  class TestHaveFunc < TestMkmf
    def test_have_func
      assert_equal(true, have_func("ruby_init"), MKMFLOG)
      assert_include($defs, '-DHAVE_RUBY_INIT')
    end

    def test_not_have_func
      assert_equal(false, have_func("no_ruby_init"), MKMFLOG)
      assert_not_include($defs, '-DHAVE_RUBY_INIT')
    end
  end
end
