# frozen_string_literal: true

require_relative "test_helper"

module Prism
  # These tests are simply to exercise snippets found by the fuzzer that caused invalid memory access.
  class FuzzerTest < TestCase
    def self.snippet(name, source)
      define_method(:"test_fuzzer_#{name}") { Prism.dump(source) }
    end

    snippet "incomplete global variable", "$"
    snippet "incomplete symbol", ":"
    snippet "incomplete escaped string", '"\\'
    snippet "trailing comment", "1\n#\n"
    snippet "comment followed by whitespace at end of file", "1\n#\n "
    snippet "trailing asterisk", "a *"
    snippet "incomplete decimal number", "0d"
    snippet "incomplete binary number", "0b"
    snippet "incomplete octal number", "0o"
    snippet "incomplete hex number", "0x"
    snippet "incomplete escaped list", "%w[\\"
    snippet "incomplete escaped regex", "/a\\"
    snippet "unterminated heredoc with unterminated escape at end of file", "<<A\n\\"
    snippet "escaped octal at end of file 1", '"\\3'
    snippet "escaped octal at end of file 2", '"\\33'
    snippet "escaped hex at end of file 1", '"\\x'
    snippet "escaped hex at end of file 2", '"\\x3'
    snippet "escaped unicode at end of file 1", '"\\u{3'
    snippet "escaped unicode at end of file 2", '"\\u{33'
    snippet "escaped unicode at end of file 3", '"\\u{333'
    snippet "escaped unicode at end of file 4", '"\\u{3333'
    snippet "escaped unicode at end of file 5", '"\\u{33333'
    snippet "escaped unicode at end of file 6", '"\\u{333333'
    snippet "escaped unicode at end of file 7", '"\\u3'
    snippet "escaped unicode at end of file 8", '"\\u33'
    snippet "escaped unicode at end of file 9", '"\\u333'
    snippet "float suffix at end of file", "1e"

    snippet "statements node with multiple heredocs", <<~EOF
      for <<A + <<B
      A
      B
    EOF
    snippet "create a binary call node with arg before receiver", <<~EOF
      <<-A.g/{/
      A
      /, ""\\
    EOF
    snippet "regular expression with start and end out of order", <<~RUBY
      <<-A.g//,
      A
      /{/, ''\\
    RUBY
    snippet "interpolated regular expression with start and end out of order", <<~RUBY
      <<-A.g/{/,
      A
      a
      /{/, ''\\
    RUBY

    snippet "parameter name that is zero length", "a { |b;"
  end
end
