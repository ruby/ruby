# frozen_string_literal: true

require_relative "test_helper"

module Prism
  class SnippetsTest < TestCase
    except = [
      "encoding_binary.txt",
      "newline_terminated.txt",
      "seattlerb/begin_rescue_else_ensure_no_bodies.txt",
      "seattlerb/case_in.txt",
      "seattlerb/parse_line_defn_no_parens.txt",
      "seattlerb/pct_nl.txt",
      "seattlerb/str_heredoc_interp.txt",
      "spanning_heredoc_newlines.txt",
      "unparser/corpus/semantic/dstr.txt",
      "whitequark/dedenting_heredoc.txt",
      "whitequark/multiple_pattern_matches.txt"
    ]

    Fixture.each(except: except) do |fixture|
      define_method(fixture.test_name) { assert_snippets(fixture) }
    end

    private

    # We test every snippet (separated by \n\n) in isolation to ensure the
    # parser does not try to read bytes further than the end of each snippet.
    def assert_snippets(fixture)
      fixture.read.split(/(?<=\S)\n\n(?=\S)/).each do |snippet|
        snippet = snippet.rstrip

        result = Prism.parse(snippet, filepath: fixture.path)
        assert result.success?

        if !ENV["PRISM_BUILD_MINIMAL"]
          dumped = Prism.dump(snippet, filepath: fixture.path)
          assert_equal_nodes(result.value, Prism.load(snippet, dumped).value)
        end
      end
    end
  end
end
