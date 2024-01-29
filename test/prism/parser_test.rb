# frozen_string_literal: true

require_relative "test_helper"

begin
  require "parser/current"
rescue LoadError
  # In CRuby's CI, we're not going to test against the parser gem because we
  # don't want to have to install it. So in this case we'll just skip this test.
  return
end

# First, opt in to every AST feature.
Parser::Builders::Default.modernize

# Modify the source map == check so that it doesn't check against the node
# itself so we don't get into a recursive loop.
Parser::Source::Map.prepend(
  Module.new {
    def ==(other)
      self.class == other.class &&
        (instance_variables - %i[@node]).map do |ivar|
          instance_variable_get(ivar) == other.instance_variable_get(ivar)
        end.reduce(:&)
    end
  }
)

# Next, ensure that we're comparing the nodes and also comparing the source
# ranges so that we're getting all of the necessary information.
Parser::AST::Node.prepend(
  Module.new {
    def ==(other)
      super && (location == other.location)
    end
  }
)

module Prism
  class ParserTest < TestCase
    base = File.join(__dir__, "fixtures")

    # These files are either failing to parse or failing to translate, so we'll
    # skip them for now.
    skip_all = %w[
      arrays.txt
      constants.txt
      dash_heredocs.txt
      dos_endings.txt
      embdoc_no_newline_at_end.txt
      heredocs_with_ignored_newlines.txt
      regex.txt
      spanning_heredoc.txt
      spanning_heredoc_newlines.txt
      tilde_heredocs.txt
      unescaping.txt
    ]

    # Not sure why these files are failing on JRuby, but skipping them for now.
    if RUBY_ENGINE == "jruby"
      skip_all.push("emoji_method_calls.txt", "symbols.txt")
    end

    # These files are failing to translate their lexer output into the lexer
    # output expected by the parser gem, so we'll skip them for now.
    skip_tokens = %w[
      comments.txt
      endless_range_in_conditional.txt
      heredoc_with_comment.txt
      heredoc_with_escaped_newline_at_start.txt
      heredocs_leading_whitespace.txt
      heredocs_nested.txt
      heredocs_with_ignored_newlines_and_non_empty.txt
      indented_file_end.txt
      non_alphanumeric_methods.txt
      range_begin_open_inclusive.txt
      single_quote_heredocs.txt
      strings.txt
      xstring.txt
    ]

    Dir["*.txt", base: base].each do |name|
      next if skip_all.include?(name)

      define_method("test_#{name}") do
        assert_equal_parses(File.join(base, name), compare_tokens: !skip_tokens.include?(name))
      end
    end

    private

    def assert_equal_parses(filepath, compare_tokens: true)
      buffer = Parser::Source::Buffer.new(filepath, 1)
      buffer.source = File.read(filepath)

      parser = Parser::CurrentRuby.default_parser
      parser.diagnostics.consumer = ->(*) {}
      parser.diagnostics.all_errors_are_fatal = true

      expected_ast, expected_comments, expected_tokens =
        begin
          parser.tokenize(buffer)
        rescue ArgumentError, Parser::SyntaxError
          return
        end

      actual_ast, actual_comments, actual_tokens =
        Prism::Translation::Parser.new.tokenize(buffer)

      assert_equal expected_ast, actual_ast, -> { assert_equal_asts_message(expected_ast, actual_ast) }
      assert_equal_tokens(expected_tokens, actual_tokens) if compare_tokens
      assert_equal_comments(expected_comments, actual_comments)
    end

    def assert_equal_asts_message(expected_ast, actual_ast)
      queue = [[expected_ast, actual_ast]]

      while (left, right = queue.shift)
        if left.type != right.type
          return "expected: #{left.type}\nactual: #{right.type}"
        end

        if left.location != right.location
          return "expected:\n#{left.inspect}\n#{left.location}\nactual:\n#{right.inspect}\n#{right.location}"
        end

        if left.type == :str && left.children[0] != right.children[0]
          return "expected: #{left.inspect}\nactual: #{right.inspect}"
        end

        left.children.zip(right.children).each do |left_child, right_child|
          queue << [left_child, right_child] if left_child.is_a?(Parser::AST::Node)
        end
      end

      "expected: #{expected_ast.inspect}\nactual: #{actual_ast.inspect}"
    end

    def assert_equal_tokens(expected_tokens, actual_tokens)
      if expected_tokens != actual_tokens
        expected_index = 0
        actual_index = 0

        while expected_index < expected_tokens.length
          expected_token = expected_tokens[expected_index]
          actual_token = actual_tokens[actual_index]

          expected_index += 1
          actual_index += 1

          # The parser gem always has a space before a string end in list
          # literals, but we don't. So we'll skip over the space.
          if expected_token[0] == :tSPACE && actual_token[0] == :tSTRING_END
            expected_index += 1
            next
          end

          # There are a lot of tokens that have very specific meaning according
          # to the context of the parser. We don't expose that information in
          # prism, so we need to normalize these tokens a bit.
          case actual_token[0]
          when :kDO
            actual_token[0] = expected_token[0] if %i[kDO_BLOCK kDO_LAMBDA].include?(expected_token[0])
          when :tLPAREN
            actual_token[0] = expected_token[0] if expected_token[0] == :tLPAREN2
          when :tLCURLY
            actual_token[0] = expected_token[0] if %i[tLBRACE tLBRACE_ARG].include?(expected_token[0])
          when :tPOW
            actual_token[0] = expected_token[0] if expected_token[0] == :tDSTAR
          end

          # Now we can assert that the tokens are actually equal.
          assert_equal expected_token, actual_token, -> {
            "expected: #{expected_token.inspect}\n" \
            "actual: #{actual_token.inspect}"
          }
        end
      end
    end

    def assert_equal_comments(expected_comments, actual_comments)
      assert_equal expected_comments, actual_comments, -> {
        "expected: #{expected_comments.inspect}\n" \
        "actual: #{actual_comments.inspect}"
      }
    end
  end
end
