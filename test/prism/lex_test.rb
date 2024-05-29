# frozen_string_literal: true

return if !(RUBY_ENGINE == "ruby" && RUBY_VERSION >= "3.2.0")

require_relative "test_helper"

module Prism
  class LexTest < TestCase
    except = [
      # It seems like there are some oddities with nested heredocs and ripper.
      # Waiting for feedback on https://bugs.ruby-lang.org/issues/19838.
      "seattlerb/heredoc_nested.txt",
      "whitequark/dedenting_heredoc.txt",
      # Ripper seems to have a bug that the regex portions before and after
      # the heredoc are combined into a single token. See
      # https://bugs.ruby-lang.org/issues/19838.
      "spanning_heredoc.txt",
      "spanning_heredoc_newlines.txt"
    ]

    if RUBY_VERSION < "3.3.0"
      # This file has changed behavior in Ripper in Ruby 3.3, so we skip it if
      # we're on an earlier version.
      except << "seattlerb/pct_w_heredoc_interp_nested.txt"

      # Ruby < 3.3.0 cannot parse heredocs where there are leading whitespace
      # characters in the heredoc start.
      # Example: <<~'   EOF' or <<-'  EOF'
      # https://bugs.ruby-lang.org/issues/19539
      except << "heredocs_leading_whitespace.txt"
    end

    Fixture.each(except: except) do |fixture|
      define_method(fixture.test_name) { assert_lex(fixture) }
    end

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

    private

    def assert_lex(fixture)
      source = fixture.read

      result = Prism.lex_compat(source)
      assert_equal [], result.errors

      Prism.lex_ripper(source).zip(result.value).each do |(ripper, prism)|
        assert_equal ripper, prism
      end
    end
  end
end
