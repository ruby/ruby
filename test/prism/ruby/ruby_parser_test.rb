# frozen_string_literal: true

return if RUBY_ENGINE == "jruby"

require_relative "../test_helper"

begin
  require "ruby_parser"
rescue LoadError
  # In CRuby's CI, we're not going to test against the ruby_parser gem because
  # we don't want to have to install it. So in this case we'll just skip this
  # test.
  return
end

module Prism
  class RubyParserTest < TestCase
    todos = [
      "encoding_euc_jp.txt",
      "regex_char_width.txt",
      "seattlerb/masgn_colon3.txt",
      "seattlerb/messy_op_asgn_lineno.txt",
      "seattlerb/op_asgn_primary_colon_const_command_call.txt",
      "seattlerb/regexp_esc_C_slash.txt",
      "seattlerb/str_lit_concat_bad_encodings.txt",
      "strings.txt",
      "unescaping.txt",
      "whitequark/masgn_const.txt",
      "whitequark/pattern_matching_constants.txt",
      "whitequark/pattern_matching_single_match.txt",
      "whitequark/ruby_bug_12402.txt",
    ]

    # https://github.com/seattlerb/ruby_parser/issues/344
    failures = [
      "alias.txt",
      "dsym_str.txt",
      "dos_endings.txt",
      "heredocs_with_fake_newlines.txt",
      "heredocs_with_ignored_newlines.txt",
      "leading_logical.txt",
      "method_calls.txt",
      "methods.txt",
      "multi_write.txt",
      "not.txt",
      "patterns.txt",
      "regex.txt",
      "seattlerb/and_multi.txt",
      "seattlerb/heredoc__backslash_dos_format.txt",
      "seattlerb/heredoc_bad_hex_escape.txt",
      "seattlerb/heredoc_bad_oct_escape.txt",
      "seattlerb/heredoc_with_extra_carriage_horrible_mix.txt",
      "seattlerb/heredoc_with_extra_carriage_returns_windows.txt",
      "seattlerb/heredoc_with_only_carriage_returns_windows.txt",
      "seattlerb/heredoc_with_only_carriage_returns.txt",
      "spanning_heredoc_newlines.txt",
      "spanning_heredoc.txt",
      "symbols.txt",
      "tilde_heredocs.txt",
      "unparser/corpus/literal/literal.txt",
      "while.txt",
      "whitequark/cond_eflipflop.txt",
      "whitequark/cond_iflipflop.txt",
      "whitequark/cond_match_current_line.txt",
      "whitequark/dedenting_heredoc.txt",
      "whitequark/lvar_injecting_match.txt",
      "whitequark/not.txt",
      "whitequark/numparam_ruby_bug_19025.txt",
      "whitequark/op_asgn_cmd.txt",
      "whitequark/parser_bug_640.txt",
      "whitequark/parser_slash_slash_n_escaping_in_literals.txt",
      "whitequark/pattern_matching_single_line_allowed_omission_of_parentheses.txt",
      "whitequark/pattern_matching_single_line.txt",
      "whitequark/ruby_bug_11989.txt",
      "whitequark/ruby_bug_18878.txt",
      "whitequark/ruby_bug_19281.txt",
      "whitequark/slash_newline_in_heredocs.txt",

      # Ruby >= 3.5 specific syntax
      "endless_methods_command_call.txt",
    ]

    Fixture.each(except: failures) do |fixture|
      define_method(fixture.test_name) do
        assert_ruby_parser(fixture, todos.include?(fixture.path))
      end
    end

    private

    def assert_ruby_parser(fixture, allowed_failure)
      source = fixture.read
      expected = ignore_warnings { ::RubyParser.new.parse(source, fixture.path) }
      actual = Prism::Translation::RubyParser.new.parse(source, fixture.path)
      on_failure = -> { message(expected, actual) }

      if !allowed_failure
        assert_equal(expected, actual, on_failure)

        unless actual.nil?
          assert_equal(expected.line, actual.line, on_failure)
          assert_equal(expected.file, actual.file, on_failure)
        end
      elsif expected == actual && expected.line && actual.line && expected.file == actual.file
        puts "#{name} now passes"
      end
    end

    def message(expected, actual)
      if expected == actual
        nil
      elsif expected.is_a?(Sexp) && actual.is_a?(Sexp)
        if expected.line != actual.line
          "expected: (#{expected.inspect} line=#{expected.line}), actual: (#{actual.inspect} line=#{actual.line})"
        elsif expected.file != actual.file
          "expected: (#{expected.inspect} file=#{expected.file}), actual: (#{actual.inspect} file=#{actual.file})"
        elsif expected.length != actual.length
          "expected: (#{expected.inspect} length=#{expected.length}), actual: (#{actual.inspect} length=#{actual.length})"
        else
          expected.zip(actual).find do |expected_field, actual_field|
            result = message(expected_field, actual_field)
            break result if result
          end
        end
      else
        "expected: #{expected.inspect}, actual: #{actual.inspect}"
      end
    end
  end
end
