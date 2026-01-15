# frozen_string_literal: true

require_relative "../test_helper"

module Prism
  class HeredocTest < TestCase
    def test_heredoc?
      refute Prism.parse_statement("\"foo\"").heredoc?
      refute Prism.parse_statement("\"foo \#{1}\"").heredoc?
      refute Prism.parse_statement("`foo`").heredoc?
      refute Prism.parse_statement("`foo \#{1}`").heredoc?

      assert Prism.parse_statement("<<~HERE\nfoo\nHERE\n").heredoc?
      assert Prism.parse_statement("<<~HERE\nfoo \#{1}\nHERE\n").heredoc?
      assert Prism.parse_statement("<<~`HERE`\nfoo\nHERE\n").heredoc?
      assert Prism.parse_statement("<<~`HERE`\nfoo \#{1}\nHERE\n").heredoc?
    end
  end
end
