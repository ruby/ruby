# frozen_string_literal: true

require_relative "../../spec_helper"

module SyntaxSuggest
  RSpec.describe Capture::FallingIndentLines do
    it "on_falling_indent" do
      source = <<~EOM
        class OH
          def lol
            print 'lol
          end

          def hello
            it "foo" do
          end

          def yolo
            print 'haha'
          end
        end
      EOM

      code_lines = CleanDocument.new(source: source).call.lines
      block = CodeBlock.new(lines: code_lines[6])

      lines = []
      Capture::FallingIndentLines.new(
        block: block,
        code_lines: code_lines
      ).call do |line|
        lines << line
      end
      lines.sort!

      expect(lines.join).to eq(<<~EOM)
        class OH
          def hello
          end
        end
      EOM
    end
  end
end
