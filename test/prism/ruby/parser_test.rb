# frozen_string_literal: true

require_relative "../test_helper"

begin
  verbose, $VERBOSE = $VERBOSE, nil
  require "parser/ruby33"
  require "prism/translation/parser33"
  require "prism/translation/parser34"
rescue LoadError
  # In CRuby's CI, we're not going to test against the parser gem because we
  # don't want to have to install it. So in this case we'll just skip this test.
  return
ensure
  $VERBOSE = verbose
end

# First, opt in to every AST feature.
Parser::Builders::Default.modernize
Prism::Translation::Parser::Builder.modernize

# The parser gem rejects some strings that would most likely lead to errors
# in consumers due to encoding problems. RuboCop however monkey-patches this
# method out in order to accept such code.
# https://github.com/whitequark/parser/blob/v3.3.6.0/lib/parser/builders/default.rb#L2289-L2295
Parser::Builders::Default.prepend(
  Module.new {
    def string_value(token)
      value(token)
    end
  }
)

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
    # These files contain code with valid syntax that can't be parsed.
    skip_syntax_error = [
      # alias/undef with %s(abc) symbol literal
      "alias.txt",
      "seattlerb/bug_215.txt",

      # 1.. && 2
      "ranges.txt",

      # Cannot yet handling leading logical operators.
      "leading_logical.txt",

      # Ruby >= 3.5 specific syntax
      "endless_methods_command_call.txt",
    ]

    # These files contain code that is being parsed incorrectly by the parser
    # gem, and therefore we don't want to compare against our translation.
    skip_incorrect = [
      # https://github.com/whitequark/parser/issues/1017
      "spanning_heredoc.txt",
      "spanning_heredoc_newlines.txt",

      # https://github.com/whitequark/parser/issues/1021
      "seattlerb/heredoc_nested.txt",

      # https://github.com/whitequark/parser/issues/1016
      "whitequark/unary_num_pow_precedence.txt",

      # https://github.com/whitequark/parser/issues/950
      "whitequark/dedenting_interpolating_heredoc_fake_line_continuation.txt",

      # Contains an escaped multibyte character. This is supposed to drop to backslash
      "seattlerb/regexp_escape_extended.txt",

      # https://github.com/whitequark/parser/issues/1020
      # These contain consecutive \r characters, followed by \n. Prism only receives
      # the already modified source buffer which dropped one \r but must know the
      # original code to parse it correctly.
      "seattlerb/heredoc_with_extra_carriage_returns_windows.txt",
      "seattlerb/heredoc_with_only_carriage_returns_windows.txt",
      "seattlerb/heredoc_with_only_carriage_returns.txt",

      # https://github.com/whitequark/parser/issues/1026
      # Regex with \c escape
      "unescaping.txt",
      "seattlerb/regexp_esc_C_slash.txt",
    ]

    # These files are failing to translate their lexer output into the lexer
    # output expected by the parser gem, so we'll skip them for now.
    skip_tokens = [
      "dash_heredocs.txt",
      "embdoc_no_newline_at_end.txt",
      "methods.txt",
      "seattlerb/bug169.txt",
      "seattlerb/case_in.txt",
      "seattlerb/difficult4__leading_dots2.txt",
      "seattlerb/difficult6__7.txt",
      "seattlerb/difficult6__8.txt",
      "seattlerb/heredoc_unicode.txt",
      "seattlerb/parse_line_heredoc.txt",
      "seattlerb/pct_w_heredoc_interp_nested.txt",
      "seattlerb/required_kwarg_no_value.txt",
      "seattlerb/TestRubyParserShared.txt",
      "unparser/corpus/literal/assignment.txt",
      "unparser/corpus/literal/literal.txt",
      "whitequark/args.txt",
      "whitequark/beginless_erange_after_newline.txt",
      "whitequark/beginless_irange_after_newline.txt",
      "whitequark/forward_arg_with_open_args.txt",
      "whitequark/kwarg_no_paren.txt",
      "whitequark/lbrace_arg_after_command_args.txt",
      "whitequark/multiple_pattern_matches.txt",
      "whitequark/newline_in_hash_argument.txt",
      "whitequark/pattern_matching_expr_in_paren.txt",
      "whitequark/pattern_matching_hash.txt",
      "whitequark/ruby_bug_14690.txt",
      "whitequark/ruby_bug_9669.txt",
      "whitequark/space_args_arg_block.txt",
      "whitequark/space_args_block.txt"
    ]

    Fixture.each(except: skip_syntax_error) do |fixture|
      define_method(fixture.test_name) do
        assert_equal_parses(
          fixture,
          compare_asts: !skip_incorrect.include?(fixture.path),
          compare_tokens: !skip_tokens.include?(fixture.path),
          compare_comments: fixture.path != "embdoc_no_newline_at_end.txt"
        )
      end
    end

    def test_non_prism_builder_class_deprecated
      warnings = capture_warnings { Prism::Translation::Parser33.new(Parser::Builders::Default.new) }

      assert_include(warnings, "#{__FILE__}:#{__LINE__ - 2}")
      assert_include(warnings, "is not a `Prism::Translation::Parser::Builder` subclass")

      warnings = capture_warnings { Prism::Translation::Parser33.new }
      assert_empty(warnings)
    end

    if RUBY_VERSION >= "3.3"
      def test_current_parser_for_current_ruby
        major, minor, _patch = Gem::Version.new(RUBY_VERSION).segments
        # Let's just hope there never is a Ruby 3.10 or similar
        expected = major * 10 + minor
        assert_equal(expected, Translation::ParserCurrent.new.version)
      end
    end

    def test_invalid_syntax
      code = <<~RUBY
        foo do
          case bar
          when
          end
        end
      RUBY
      buffer = Parser::Source::Buffer.new("(string)")
      buffer.source = code

      parser = Prism::Translation::Parser33.new
      parser.diagnostics.all_errors_are_fatal = true
      assert_raise(Parser::SyntaxError) { parser.tokenize(buffer) }
    end

    def test_it_block_parameter_syntax
      it_fixture_path = Pathname(__dir__).join("../../../test/prism/fixtures/it.txt")

      buffer = Parser::Source::Buffer.new(it_fixture_path)
      buffer.source = it_fixture_path.read
      actual_ast = Prism::Translation::Parser34.new.tokenize(buffer)[0]

      it_block_parameter_sexp = parse_sexp {
        s(:begin,
        s(:itblock,
          s(:send, nil, :x), :it,
          s(:lvar, :it)),
        s(:itblock,
          s(:lambda), :it,
          s(:lvar, :it)))
      }

      assert_equal(it_block_parameter_sexp, actual_ast.to_sexp)
    end

    private

    def assert_equal_parses(fixture, compare_asts: true, compare_tokens: true, compare_comments: true)
      buffer = Parser::Source::Buffer.new(fixture.path, 1)
      buffer.source = fixture.read

      parser = Parser::Ruby33.new
      parser.diagnostics.consumer = ->(*) {}
      parser.diagnostics.all_errors_are_fatal = true

      expected_ast, expected_comments, expected_tokens =
        ignore_warnings { parser.tokenize(buffer) }

      actual_ast, actual_comments, actual_tokens =
        ignore_warnings { Prism::Translation::Parser33.new.tokenize(buffer) }

      if expected_ast == actual_ast
        if !compare_asts && !Fixture.custom_base_path?
          puts "#{fixture.path} is now passing"
        end

        assert_equal expected_ast, actual_ast, -> { assert_equal_asts_message(expected_ast, actual_ast) }

        begin
          assert_equal_tokens(expected_tokens, actual_tokens)
        rescue Test::Unit::AssertionFailedError
          raise if compare_tokens
        else
          puts "#{fixture.path} is now passing" if !compare_tokens && !Fixture.custom_base_path?
        end

        assert_equal_comments(expected_comments, actual_comments) if compare_comments
      elsif compare_asts
        assert_equal expected_ast, actual_ast, -> { assert_equal_asts_message(expected_ast, actual_ast) }
      end
    end

    def assert_equal_asts_message(expected_ast, actual_ast)
      queue = [[expected_ast, actual_ast]]

      while (left, right = queue.shift)
        if left.type != right.type
          return "expected: #{left.type}\nactual: #{right.type}"
        end

        if left.location != right.location
          return "expected:\n#{left.inspect}\n#{left.location.inspect}\nactual:\n#{right.inspect}\n#{right.location.inspect}"
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
        index = 0
        max_index = [expected_tokens, actual_tokens].map(&:size).max

        while index <= max_index
          expected_token = expected_tokens.fetch(index, [])
          actual_token = actual_tokens.fetch(index, [])

          index += 1

          # There are a lot of tokens that have very specific meaning according
          # to the context of the parser. We don't expose that information in
          # prism, so we need to normalize these tokens a bit.
          if expected_token[0] == :kDO_BLOCK && actual_token[0] == :kDO
            actual_token[0] = expected_token[0]
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

    def parse_sexp(&block)
      Class.new { extend AST::Sexp }.instance_eval(&block).to_sexp
    end
  end
end
