# frozen_string_literal: false
require_relative 'base'
require 'tempfile'

class TestMkmf
  class TestHaveMacro < TestMkmf
    MACRO_NAME = "RUBY_MKMFTEST_FOOBAR"

    def test_have_macro_opt
      assert_equal(true, have_macro(MACRO_NAME, nil, "-D#{MACRO_NAME}"), MKMFLOG)
    end

    def test_have_macro_header
      Tempfile.create(%w"test_mkmf .h", ".") do |tmp|
        tmp.puts("#undef #{MACRO_NAME}")
        tmp.puts("#define #{MACRO_NAME} 1")
        tmp.close
        base = File.basename(tmp.path)
        assert_equal(true, have_macro(MACRO_NAME, base, "-I."), MKMFLOG)
      end
    end

    def test_not_have_macro_opt
      assert_equal(false, have_macro(MACRO_NAME, nil, "-U#{MACRO_NAME}"), MKMFLOG)
    end

    def test_not_have_macro_header
      Tempfile.create(%w"test_mkmf .h", ".") do |tmp|
        tmp.puts("#undef #{MACRO_NAME}")
        tmp.close
        base = File.basename(tmp.path)
        assert_equal(false, have_macro(MACRO_NAME, base, "-I."), MKMFLOG)
      end
    end
  end
end
