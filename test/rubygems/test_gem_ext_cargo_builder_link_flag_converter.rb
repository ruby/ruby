# frozen_string_literal: true
require_relative "helper"
require "rubygems/ext"
require "rubygems/ext/cargo_builder/link_flag_converter"

class TestGemExtCargoBuilderLinkFlagConverter < Gem::TestCase
  CASES = {
    test_search_path_basic: ["-L/usr/local/lib", ["-L", "native=/usr/local/lib"]],
    test_search_path_space: ["-L /usr/local/lib", ["-L", "native=/usr/local/lib"]],
    test_search_path_space_in_path: ["-L/usr/local/my\ lib", ["-L", "native=/usr/local/my\ lib"]],
    test_simple_lib: ["-lfoo", ["-l", "foo"]],
    test_lib_with_nonascii: ["-lws2_32", ["-l", "ws2_32"]],
    test_simple_lib_space: ["-l foo", ["-l", "foo"]],
    test_verbose_lib_space: ["--library=foo", ["-l", "foo"]],
    test_libstatic_with_colon: ["-l:libssp.a", ["-l", "static=ssp"]],
    test_libstatic_with_colon_space: ["-l :libssp.a", ["-l", "static=ssp"]],
    test_unconventional_lib_with_colon: ["-l:ssp.a", ["-C", "link_arg=-l:ssp.a"]],
    test_dylib_with_colon_space: ["-l :libssp.dylib", ["-l", "dylib=ssp"]],
    test_so_with_colon_space: ["-l :libssp.so", ["-l", "dylib=ssp"]],
    test_dll_with_colon_space: ["-l :libssp.dll", ["-l", "dylib=ssp"]],
    test_framework: ["-F/some/path", ["-l", "framework=/some/path"]],
    test_framework_space: ["-F /some/path", ["-l", "framework=/some/path"]],
    test_non_lib_dash_l: ["test_rubygems_20220413-976-lemgf9/prefix", ["-C", "link_arg=test_rubygems_20220413-976-lemgf9/prefix"]],
  }.freeze

  CASES.each do |test_name, (arg, expected)|
    raise "duplicate test name" if instance_methods.include?(test_name)

    define_method(test_name) do
      assert_equal(expected, Gem::Ext::CargoBuilder::LinkFlagConverter.convert(arg))
    end
  end
end
