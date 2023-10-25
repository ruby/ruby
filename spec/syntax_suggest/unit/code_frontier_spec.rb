# frozen_string_literal: true

require_relative "../spec_helper"

module SyntaxSuggest
  RSpec.describe CodeFrontier do
    it "detect_bad_blocks" do
      code_lines = code_line_array(<<~EOM)
        describe "lol" do
          end
        end

        it "lol" do
          end
        end
      EOM

      frontier = CodeFrontier.new(code_lines: code_lines)
      blocks = []
      blocks << CodeBlock.new(lines: code_lines[1])
      blocks << CodeBlock.new(lines: code_lines[5])
      blocks.each do |b|
        frontier << b
      end

      expect(frontier.detect_invalid_blocks.sort).to eq(blocks.sort)
    end

    it "self.combination" do
      expect(
        CodeFrontier.combination([:a, :b, :c, :d])
      ).to eq(
        [
          [:a], [:b], [:c], [:d],
          [:a, :b],
          [:a, :c],
          [:a, :d],
          [:b, :c],
          [:b, :d],
          [:c, :d],
          [:a, :b, :c],
          [:a, :b, :d],
          [:a, :c, :d],
          [:b, :c, :d],
          [:a, :b, :c, :d]
        ]
      )
    end

    it "doesn't duplicate blocks" do
      code_lines = code_line_array(<<~EOM)
        def foo
          puts "lol"
          puts "lol"
          puts "lol"
        end
      EOM

      frontier = CodeFrontier.new(code_lines: code_lines)
      frontier << CodeBlock.new(lines: [code_lines[2]])
      expect(frontier.count).to eq(1)

      frontier << CodeBlock.new(lines: [code_lines[1], code_lines[2], code_lines[3]])
      # expect(frontier.count).to eq(1)
      expect(frontier.pop.to_s).to eq(<<~EOM.indent(2))
        puts "lol"
        puts "lol"
        puts "lol"
      EOM

      expect(frontier.pop).to be_nil

      code_lines = code_line_array(<<~EOM)
        def foo
          puts "lol"
          puts "lol"
          puts "lol"
        end
      EOM

      frontier = CodeFrontier.new(code_lines: code_lines)
      frontier << CodeBlock.new(lines: [code_lines[2]])
      expect(frontier.count).to eq(1)

      frontier << CodeBlock.new(lines: [code_lines[3]])
      expect(frontier.count).to eq(2)
      expect(frontier.pop.to_s).to eq(<<~EOM.indent(2))
        puts "lol"
      EOM
    end

    it "detects if multiple syntax errors are found" do
      code_lines = code_line_array(<<~EOM)
        def foo
          end
        end
      EOM

      frontier = CodeFrontier.new(code_lines: code_lines)

      frontier << CodeBlock.new(lines: code_lines[1])
      block = frontier.pop
      expect(block.to_s).to eq(<<~EOM.indent(2))
        end
      EOM
      frontier << block

      expect(frontier.holds_all_syntax_errors?).to be_truthy
    end

    it "detects if it has not captured all syntax errors" do
      code_lines = code_line_array(<<~EOM)
        def foo
          puts "lol"
        end

        describe "lol"
        end

        it "lol"
        end
      EOM

      frontier = CodeFrontier.new(code_lines: code_lines)
      frontier << CodeBlock.new(lines: [code_lines[1]])
      block = frontier.pop
      expect(block.to_s).to eq(<<~EOM.indent(2))
        puts "lol"
      EOM
      frontier << block

      expect(frontier.holds_all_syntax_errors?).to be_falsey
    end
  end
end
