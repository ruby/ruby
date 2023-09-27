# frozen_string_literal: true

require_relative "test_helper"

module YARP
  class HeredocDedentTest < TestCase
    filepath = File.expand_path("fixtures/tilde_heredocs.txt", __dir__)

    File.read(filepath).split(/(?=\n)\n(?=<)/).each_with_index do |heredoc, index|
      define_method "test_heredoc_#{index}" do
        node = YARP.parse(heredoc).value.statements.body.first
        if node.is_a? StringNode
          actual = node.unescaped
        else
          actual = node.parts.map { |part| part.is_a?(StringNode) ? part.unescaped : "1" }.join
        end

        assert_equal(eval(heredoc), actual, "Expected heredocs to match.")
      end
    end
  end
end
