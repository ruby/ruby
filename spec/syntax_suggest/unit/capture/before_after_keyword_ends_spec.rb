# frozen_string_literal: true

require_relative "../../spec_helper"

module SyntaxSuggest
  RSpec.describe Capture::BeforeAfterKeywordEnds do
    it "before after keyword ends" do
      source = <<~'EOM'
        def nope
          print 'not me'
        end

        def lol
          print 'lol'
        end

        def hello      #  8

        def yolo
          print 'haha'
        end

        def nada
          print 'nope'
        end
      EOM

      code_lines = CleanDocument.new(source: source).call.lines
      block = CodeBlock.new(lines: code_lines[8])

      expect(block.to_s).to include("def hello")

      lines = Capture::BeforeAfterKeywordEnds.new(
        block: block,
        code_lines: code_lines
      ).call
      lines.sort!

      expect(lines.join).to include(<<~'EOM')
        def lol
        end
        def yolo
        end
      EOM
    end
  end
end
