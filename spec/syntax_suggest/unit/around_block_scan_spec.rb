# frozen_string_literal: true

require_relative "../spec_helper"

module SyntaxSuggest
  RSpec.describe AroundBlockScan do
    it "continues scan from last location even if scan is false" do
      source = <<~EOM
        print 'omg'
        print 'lol'
        print 'haha'
      EOM
      code_lines = CodeLine.from_source(source)
      block = CodeBlock.new(lines: code_lines[1])
      expand = AroundBlockScan.new(code_lines: code_lines, block: block)
        .scan_neighbors_not_empty

      expect(expand.code_block.to_s).to eq(source)
      expand.scan_while { |line| false }

      expect(expand.code_block.to_s).to eq(source)
    end

    it "scan_adjacent_indent works on first or last line" do
      source_string = <<~EOM
        def foo
          if [options.output_format_tty, options.output_format_block].include?(nil)
            raise("Bad output mode '\#{v}'; each must be one of \#{lookups.output_formats.keys}.")
          end
        end
      EOM

      code_lines = code_line_array(source_string)
      block = CodeBlock.new(lines: code_lines[4])
      expand = AroundBlockScan.new(code_lines: code_lines, block: block)
        .scan_adjacent_indent

      expect(expand.code_block.to_s).to eq(<<~EOM)
        def foo
          if [options.output_format_tty, options.output_format_block].include?(nil)
            raise("Bad output mode '\#{v}'; each must be one of \#{lookups.output_formats.keys}.")
          end
        end
      EOM
    end

    it "expands indentation" do
      source_string = <<~EOM
        def foo
          if [options.output_format_tty, options.output_format_block].include?(nil)
            raise("Bad output mode '\#{v}'; each must be one of \#{lookups.output_formats.keys}.")
          end
        end
      EOM

      code_lines = code_line_array(source_string)
      block = CodeBlock.new(lines: code_lines[2])
      expand = AroundBlockScan.new(code_lines: code_lines, block: block)
        .stop_after_kw
        .scan_adjacent_indent

      expect(expand.code_block.to_s).to eq(<<~EOM.indent(2))
        if [options.output_format_tty, options.output_format_block].include?(nil)
          raise("Bad output mode '\#{v}'; each must be one of \#{lookups.output_formats.keys}.")
        end
      EOM
    end

    it "can stop before hitting another end" do
      source_string = <<~EOM
        def lol
        end
        def foo
          puts "lol"
        end
      EOM

      code_lines = code_line_array(source_string)
      block = CodeBlock.new(lines: code_lines[3])
      expand = AroundBlockScan.new(code_lines: code_lines, block: block)
      expand.stop_after_kw
      expand.scan_while { true }

      expect(expand.code_block.to_s).to eq(<<~EOM)
        def foo
          puts "lol"
        end
      EOM
    end

    it "captures multiple empty and hidden lines" do
      source_string = <<~EOM
        def foo
          Foo.call

            puts "lol"

          end
        end
      EOM

      code_lines = code_line_array(source_string)
      block = CodeBlock.new(lines: code_lines[3])
      expand = AroundBlockScan.new(code_lines: code_lines, block: block)
      expand.scan_while { true }

      expect(expand.lines.first.index).to eq(0)
      expect(expand.lines.last.index).to eq(6)
      expect(expand.code_block.to_s).to eq(source_string)
    end

    it "only takes what you ask" do
      source_string = <<~EOM
        def foo
          Foo.call

            puts "lol"

          end
        end
      EOM

      code_lines = code_line_array(source_string)
      block = CodeBlock.new(lines: code_lines[3])
      expand = AroundBlockScan.new(code_lines: code_lines, block: block)
      expand.scan_while { |line| line.not_empty? }

      expect(expand.code_block.to_s).to eq(<<~EOM.indent(4))
        puts "lol"
      EOM
    end

    it "skips what you want" do
      source_string = <<~EOM
        def foo
          Foo.call

            puts "haha"
            # hide me

            puts "lol"

          end
        end
      EOM

      code_lines = code_line_array(source_string)
      code_lines[4].mark_invisible

      block = CodeBlock.new(lines: code_lines[3])
      expand = AroundBlockScan.new(code_lines: code_lines, block: block)
      expand.force_add_empty
      expand.force_add_hidden
      expand.scan_neighbors_not_empty

      expect(expand.code_block.to_s).to eq(<<~EOM.indent(4))

        puts "haha"

        puts "lol"

      EOM
    end
  end
end
