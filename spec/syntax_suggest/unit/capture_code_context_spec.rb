# frozen_string_literal: true

require_relative "../spec_helper"

module SyntaxSuggest
  RSpec.describe CaptureCodeContext do
    it "capture_before_after_kws two" do
      source = <<~'EOM'
        class OH

          def hello

          def hai
          end
        end
      EOM

      code_lines = CleanDocument.new(source: source).call.lines
      block = CodeBlock.new(lines: code_lines[2])

      display = CaptureCodeContext.new(
        blocks: [block],
        code_lines: code_lines
      )
      display.capture_before_after_kws(block)
      expect(display.sorted_lines.join).to eq(<<~'EOM'.indent(2))
        def hello
        def hai
        end
      EOM
    end

    it "capture_before_after_kws" do
      source = <<~'EOM'
        def sit
        end

        def bark

        def eat
        end
      EOM

      code_lines = CleanDocument.new(source: source).call.lines
      block = CodeBlock.new(lines: code_lines[3])

      display = CaptureCodeContext.new(
        blocks: [block],
        code_lines: code_lines
      )

      lines = display.capture_before_after_kws(block).sort
      expect(lines.join).to eq(<<~'EOM')
        def sit
        end
        def bark
        def eat
        end
      EOM
    end

    it "handles ambiguous end" do
      source = <<~'EOM'
        def call          # 0
            print "lol"   # 1
          end # one       # 2
        end # two         # 3
      EOM

      code_lines = CleanDocument.new(source: source).call.lines
      code_lines[0..2].each(&:mark_invisible)
      block = CodeBlock.new(lines: code_lines)

      display = CaptureCodeContext.new(
        blocks: [block],
        code_lines: code_lines
      )
      lines = display.call

      lines = lines.sort.map(&:original)

      expect(lines.join).to eq(<<~'EOM')
        def call          # 0
          end # one       # 2
        end # two         # 3
      EOM
    end

    it "shows ends of captured block" do
      lines = fixtures_dir.join("rexe.rb.txt").read.lines
      lines.delete_at(148 - 1)
      source = lines.join

      code_lines = CleanDocument.new(source: source).call.lines

      code_lines[0..75].each(&:mark_invisible)
      code_lines[77..-1].each(&:mark_invisible)
      expect(code_lines.join.strip).to eq("class Lookups")

      block = CodeBlock.new(lines: code_lines[76..149])

      display = CaptureCodeContext.new(
        blocks: [block],
        code_lines: code_lines
      )
      lines = display.call

      lines = lines.sort.map(&:original)
      expect(lines.join).to include(<<~'EOM'.indent(2))
        class Lookups
          def format_requires
        end
      EOM
    end

    it "shows ends of captured block" do
      source = <<~'EOM'
        class Dog
          def bark
            puts "woof"
        end
      EOM

      code_lines = CleanDocument.new(source: source).call.lines
      block = CodeBlock.new(lines: code_lines)
      code_lines[1..-1].each(&:mark_invisible)

      expect(block.to_s.strip).to eq("class Dog")

      display = CaptureCodeContext.new(
        blocks: [block],
        code_lines: code_lines
      )
      lines = display.call.sort.map(&:original)
      expect(lines.join).to eq(<<~'EOM')
        class Dog
          def bark
        end
      EOM
    end

    it "captures surrounding context on falling indent" do
      source = <<~'EOM'
        class Blerg
        end

        class OH

          def hello
            it "foo" do
          end
        end

        class Zerg
        end
      EOM
      code_lines = CleanDocument.new(source: source).call.lines
      block = CodeBlock.new(lines: code_lines[6])

      expect(block.to_s.strip).to eq('it "foo" do')

      display = CaptureCodeContext.new(
        blocks: [block],
        code_lines: code_lines
      )
      lines = display.call.sort.map(&:original)
      expect(lines.join).to eq(<<~'EOM')
        class OH
          def hello
            it "foo" do
          end
        end
      EOM
    end

    it "captures surrounding context on same indent" do
      source = <<~'EOM'
        class Blerg
        end
        class OH

          def nope
          end

          def lol
          end

          end # here

          def haha
          end

          def nope
          end
        end

        class Zerg
        end
      EOM

      code_lines = CleanDocument.new(source: source).call.lines
      block = CodeBlock.new(lines: code_lines[7..10])
      expect(block.to_s).to eq(<<~'EOM'.indent(2))
        def lol
        end

        end # here
      EOM

      code_context = CaptureCodeContext.new(
        blocks: [block],
        code_lines: code_lines
      )

      lines = code_context.call
      out = DisplayCodeWithLineNumbers.new(
        lines: lines
      ).call

      expect(out).to eq(<<~'EOM'.indent(2))
         3  class OH
         8    def lol
         9    end
        11    end # here
        18  end
      EOM
    end
  end
end
