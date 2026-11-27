# frozen_string_literal: false
require 'test/unit'
require 'mkmf'

class TestMkmfGlobal < Test::Unit::TestCase
  main = TOPLEVEL_BINDING.receiver
  MakeMakefile.public_instance_methods(false).each do |m|
    define_method(:"test_global_#{m}") do
      assert_respond_to(main, [m, true])
      assert_not_respond_to(main, [m, false])
    end
  end
end

class TestMkmfLinkConfig < Test::Unit::TestCase
  def test_use_configured_libruby_for_bundled_extensions
    librubyarg = RbConfig::CONFIG["LIBRUBYARG"]

    RbConfig::CONFIG["LIBRUBYARG"] = "-lruby"
    assert_include(Shellwords.shellsplit(link_command("")), "-lruby")

    RbConfig::CONFIG["LIBRUBYARG"] = "-lruby-static"
    assert_include(Shellwords.shellsplit(link_command("")), "-lruby-static")
  ensure
    RbConfig::CONFIG["LIBRUBYARG"] = librubyarg
  end
end
