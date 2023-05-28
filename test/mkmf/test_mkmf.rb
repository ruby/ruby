# frozen_string_literal: false
require 'test/unit'
require_relative 'base'

class TestMkmfGlobal < Test::Unit::TestCase
  def test_methods_not_on_main_sanity_check
    main = TOPLEVEL_BINDING.receiver
    refute main.respond_to?(:create_makefile, true),
      "global mkmf module should only be included in subprocesses during tests"
  end

  def test_methods_on_main
    assert_separately([], <<~"end;")
      alias old_message message
      require 'mkmf'
      alias message old_message # need message() for test suite
      main = TOPLEVEL_BINDING.receiver
      (MakeMakefile.public_instance_methods(false) - [:message]).each do |m|
        assert_respond_to(main, [m, true])
        assert_not_respond_to(main, [m, false])
      end
    end;
  end
end
