# frozen_string_literal: true

require "yarp_test_helper"

module YARP
  class HeredocDedentTest < Test::Unit::TestCase
    filepath = File.expand_path("fixtures/tilde_heredocs.txt", __dir__)

    File.read(filepath).split(/(?=\n)\n(?=<)/).each_with_index do |heredoc, index|
      define_method "test_heredoc_#{index}" do
        parts = YARP.parse(heredoc).value.statements.body.first.parts
        actual = parts.map { |part| part.is_a?(StringNode) ? part.unescaped : "1" }.join

        assert_equal(eval(heredoc), actual, "Expected heredocs to match.")
      end
    end
  end
end
