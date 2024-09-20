# frozen_string_literal: true

require_relative "../spec_helper"

module SyntaxSuggest
  RSpec.describe CodeBlock do
    it "can detect if it's valid or not" do
      code_lines = code_line_array(<<~EOM)
        def foo
          puts 'lol'
        end
      EOM

      block = CodeBlock.new(lines: code_lines[1])
      expect(block.valid?).to be_truthy
    end

    it "can be sorted in indentation order" do
      code_lines = code_line_array(<<~EOM)
        def foo
          puts 'lol'
            end
      EOM

      block_0 = CodeBlock.new(lines: code_lines[0])
      block_1 = CodeBlock.new(lines: code_lines[1])
      block_2 = CodeBlock.new(lines: code_lines[2])

      expect(block_0 <=> block_0.dup).to eq(0)
      expect(block_1 <=> block_0).to eq(1)
      expect(block_1 <=> block_2).to eq(-1)

      array = [block_2, block_1, block_0].sort
      expect(array.last).to eq(block_2)

      block = CodeBlock.new(lines: CodeLine.new(line: " " * 8 + "foo", index: 4, lex: []))
      array.prepend(block)
      expect(array.max).to eq(block)
    end

    it "knows it's current indentation level" do
      code_lines = code_line_array(<<~EOM)
        def foo
          puts 'lol'
        end
      EOM

      block = CodeBlock.new(lines: code_lines[1])
      expect(block.current_indent).to eq(2)

      block = CodeBlock.new(lines: code_lines[0])
      expect(block.current_indent).to eq(0)
    end

    it "knows it's current indentation level when mismatched indents" do
      code_lines = code_line_array(<<~EOM)
        def foo
          puts 'lol'
         end
      EOM

      block = CodeBlock.new(lines: [code_lines[1], code_lines[2]])
      expect(block.current_indent).to eq(1)
    end

    it "before lines and after lines" do
      code_lines = code_line_array(<<~EOM)
        def foo
          bar; end
        end
      EOM

      block = CodeBlock.new(lines: code_lines[1])
      expect(block.valid?).to be_falsey
    end
  end
end
