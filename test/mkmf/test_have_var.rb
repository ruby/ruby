# frozen_string_literal: false
require_relative 'base'
require 'tempfile'

class TestMkmf
  class TestHaveVar < TestMkmf
    def test_have_var
      assert_equal(true, have_var("ruby_version"), MKMFLOG)
      assert_include($defs, '-DHAVE_RUBY_VERSION')
    end

    def test_not_have_var
      assert_equal(false, have_var("rb_vm_something_flag"), MKMFLOG)
      assert_not_include($defs, '-DHAVE_RB_VM_SOMETHING_FLAG')
    end
  end
end
