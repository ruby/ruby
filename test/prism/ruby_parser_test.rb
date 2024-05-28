# frozen_string_literal: true

return if RUBY_ENGINE == "jruby"

require_relative "test_helper"

begin
  require "ruby_parser"
rescue LoadError
  # In CRuby's CI, we're not going to test against the ruby_parser gem because
  # we don't want to have to install it. So in this case we'll just skip this
  # test.
  return
end

# We want to also compare lines and files to make sure we're setting them
# correctly.
Sexp.prepend(
  Module.new do
    def ==(other)
      super && line == other.line && line_max == other.line_max && file == other.file
    end
  end
)

module Prism
  class RubyParserTest < TestCase
    base = File.join(__dir__, "fixtures")

    todos = %w[
      newline_terminated.txt
      regex_char_width.txt
      seattlerb/bug169.txt
      seattlerb/masgn_colon3.txt
      seattlerb/messy_op_asgn_lineno.txt
      seattlerb/op_asgn_primary_colon_const_command_call.txt
      seattlerb/regexp_esc_C_slash.txt
      seattlerb/str_lit_concat_bad_encodings.txt
      unescaping.txt
      unparser/corpus/literal/kwbegin.txt
      unparser/corpus/literal/send.txt
      whitequark/masgn_const.txt
      whitequark/ruby_bug_12402.txt
      whitequark/ruby_bug_14690.txt
      whitequark/space_args_block.txt
    ]

    # https://github.com/seattlerb/ruby_parser/issues/344
    failures = %w[
      alias.txt
      dos_endings.txt
      heredocs_with_ignored_newlines.txt
      method_calls.txt
      methods.txt
      multi_write.txt
      not.txt
      patterns.txt
      regex.txt
      seattlerb/and_multi.txt
      seattlerb/heredoc__backslash_dos_format.txt
      seattlerb/heredoc_bad_hex_escape.txt
      seattlerb/heredoc_bad_oct_escape.txt
      seattlerb/heredoc_with_extra_carriage_horrible_mix.txt
      seattlerb/heredoc_with_extra_carriage_returns_windows.txt
      seattlerb/heredoc_with_only_carriage_returns_windows.txt
      seattlerb/heredoc_with_only_carriage_returns.txt
      spanning_heredoc_newlines.txt
      spanning_heredoc.txt
      tilde_heredocs.txt
      unparser/corpus/literal/literal.txt
      while.txt
      whitequark/cond_eflipflop.txt
      whitequark/cond_iflipflop.txt
      whitequark/cond_match_current_line.txt
      whitequark/dedenting_heredoc.txt
      whitequark/lvar_injecting_match.txt
      whitequark/not.txt
      whitequark/numparam_ruby_bug_19025.txt
      whitequark/op_asgn_cmd.txt
      whitequark/parser_bug_640.txt
      whitequark/parser_slash_slash_n_escaping_in_literals.txt
      whitequark/pattern_matching_single_line_allowed_omission_of_parentheses.txt
      whitequark/pattern_matching_single_line.txt
      whitequark/ruby_bug_11989.txt
      whitequark/slash_newline_in_heredocs.txt
    ]

    Dir["**/*.txt", base: base].each do |name|
      next if failures.include?(name)

      define_method("test_#{name}") do
        begin
          # Parsing with ruby parser tends to be noisy with warnings, so we're
          # turning those off.
          previous_verbose, $VERBOSE = $VERBOSE, nil
          assert_parse_file(base, name, todos.include?(name))
        ensure
          $VERBOSE = previous_verbose
        end
      end
    end

    private

    def assert_parse_file(base, name, allowed_failure)
      filepath = File.join(base, name)
      expected = ::RubyParser.new.parse(File.read(filepath), filepath)
      actual = Prism::Translation::RubyParser.parse_file(filepath)

      if !allowed_failure
        assert_equal_nodes expected, actual
      elsif expected == actual
        puts "#{name} now passes"
      end
    end

    def assert_equal_nodes(left, right)
      return if left == right

      if left.is_a?(Sexp) && right.is_a?(Sexp)
        if left.line != right.line
          assert_equal "(#{left.inspect} line=#{left.line})", "(#{right.inspect} line=#{right.line})"
        elsif left.file != right.file
          assert_equal "(#{left.inspect} file=#{left.file})", "(#{right.inspect} file=#{right.file})"
        elsif left.length != right.length
          assert_equal "(#{left.inspect} length=#{left.length})", "(#{right.inspect} length=#{right.length})"
        else
          left.zip(right).each { |l, r| assert_equal_nodes(l, r) }
        end
      else
        assert_equal left, right
      end
    end
  end
end
