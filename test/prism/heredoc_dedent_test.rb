# frozen_string_literal: true

require_relative "test_helper"

module Prism
  class HeredocDedentTest < TestCase
    filepath = File.expand_path("fixtures/tilde_heredocs.txt", __dir__)

    File.read(filepath).split(/(?=\n)\n(?=<)/).each_with_index do |heredoc, index|
      # The first example in this file has incorrect dedent calculated by
      # TruffleRuby so we skip it.
      next if index == 0 && RUBY_ENGINE == "truffleruby"

      define_method "test_heredoc_#{index}" do
        node = Prism.parse(heredoc).value.statements.body.first

        if node.is_a?(StringNode)
          actual = node.unescaped
        else
          actual = node.parts.map { |part| part.is_a?(StringNode) ? part.unescaped : "1" }.join
        end

        assert_equal(eval(heredoc), actual, "Expected heredocs to match.")
      end
    end
  end
end
