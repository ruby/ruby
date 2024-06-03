# frozen_string_literal: true

return if RUBY_VERSION < "3.3"

require_relative "../test_helper"

module Prism
  class RipperTest < TestCase
    # Skip these tests that Ripper is reporting the wrong results for.
    incorrect = [
      # Ripper incorrectly attributes the block to the keyword.
      "seattlerb/block_break.txt",
      "seattlerb/block_next.txt",
      "seattlerb/block_return.txt",
      "whitequark/break_block.txt",
      "whitequark/next_block.txt",
      "whitequark/return_block.txt",

      # Ripper is not accounting for locals created by patterns using the **
      # operator within an `in` clause.
      "seattlerb/parse_pattern_058.txt",

      # Ripper cannot handle named capture groups in regular expressions.
      "regex.txt",
      "regex_char_width.txt",
      "whitequark/lvar_injecting_match.txt",

      # Ripper fails to understand some structures that span across heredocs.
      "spanning_heredoc.txt"
    ]

    # Skip these tests that we haven't implemented yet.
    omitted = [
      "dos_endings.txt",
      "heredocs_with_ignored_newlines.txt",
      "seattlerb/block_call_dot_op2_brace_block.txt",
      "seattlerb/block_command_operation_colon.txt",
      "seattlerb/block_command_operation_dot.txt",
      "seattlerb/heredoc__backslash_dos_format.txt",
      "seattlerb/heredoc_backslash_nl.txt",
      "seattlerb/heredoc_nested.txt",
      "seattlerb/heredoc_squiggly_blank_line_plus_interpolation.txt",
      "tilde_heredocs.txt",
      "unparser/corpus/semantic/dstr.txt",
      "whitequark/dedenting_heredoc.txt",
      "whitequark/parser_drops_truncated_parts_of_squiggly_heredoc.txt",
      "whitequark/parser_slash_slash_n_escaping_in_literals.txt",
      "whitequark/send_block_chain_cmd.txt",
      "whitequark/slash_newline_in_heredocs.txt"
    ]

    Fixture.each(except: incorrect | omitted) do |fixture|
      define_method(fixture.test_name) { assert_ripper(fixture.read) }
    end

    private

    def assert_ripper(source)
      assert_equal Ripper.sexp_raw(source), Prism::Translation::Ripper.sexp_raw(source)
    end
  end
end
