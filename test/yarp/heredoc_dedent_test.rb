# frozen_string_literal: true

require "test_helper"

module YARP
  class HeredocDedentTest < Test::Unit::TestCase
    filepath = File.expand_path("fixtures/tilde_heredocs.rb", __dir__)

    File.read(filepath).split(/(?=\n)\n(?=<)/).each_with_index do |heredoc, index|
      test "heredoc #{index}" do
        parts = YARP.parse(heredoc).value.statements.body.first.parts
        actual = parts.map { |part| part.is_a?(StringNode) ? part.unescaped : "1" }.join

        assert_equal(eval(heredoc), actual, "Expected heredocs to match.")
      end
    end
  end
end
