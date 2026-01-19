# frozen_string_literal: true

return if !(RUBY_ENGINE == "ruby" && RUBY_VERSION >= "3.2.0")

require_relative "test_helper"

module Prism
  class LexTest < TestCase
    def test_lex_file
      assert_nothing_raised do
        Prism.lex_file(__FILE__)
      end

      error = assert_raise Errno::ENOENT do
        Prism.lex_file("idontexist.rb")
      end

      assert_equal "No such file or directory - idontexist.rb", error.message

      assert_raise TypeError do
        Prism.lex_file(nil)
      end
    end

    def test_parse_lex
      node, tokens = Prism.parse_lex("def foo; end").value

      assert_kind_of ProgramNode, node
      assert_equal 5, tokens.length
    end

    def test_parse_lex_file
      node, tokens = Prism.parse_lex_file(__FILE__).value

      assert_kind_of ProgramNode, node
      refute_empty tokens

      error = assert_raise Errno::ENOENT do
        Prism.parse_lex_file("idontexist.rb")
      end

      assert_equal "No such file or directory - idontexist.rb", error.message

      assert_raise TypeError do
        Prism.parse_lex_file(nil)
      end
    end

    if RUBY_VERSION >= "3.3"
      def test_lex_compare
        prism = Prism.lex_compat(File.read(__FILE__), version: "current").value
        ripper = Prism.lex_ripper(File.read(__FILE__))
        assert_equal(ripper, prism)
      end
    end
  end
end
