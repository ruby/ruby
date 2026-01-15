# frozen_string_literal: true

require_relative "../spec_helper"

module SyntaxSuggest
  RSpec.describe DisplayInvalidBlocks do
    it "works with valid code" do
      syntax_string = <<~EOM
        class OH
          def hello
          end
          def hai
          end
        end
      EOM

      search = CodeSearch.new(syntax_string)
      search.call

      io = StringIO.new
      display = DisplayInvalidBlocks.new(
        io: io,
        blocks: search.invalid_blocks,
        terminal: false,
        code_lines: search.code_lines
      )
      display.call
      expect(io.string).to include("")
    end

    it "selectively prints to terminal if input is a tty by default" do
      source = <<~EOM
        class OH
          def hello
          def hai
          end
        end
      EOM

      code_lines = CleanDocument.new(source: source).call.lines

      io = StringIO.new
      def io.isatty
        true
      end

      block = CodeBlock.new(lines: code_lines[1])
      display = DisplayInvalidBlocks.new(
        io: io,
        blocks: block,
        code_lines: code_lines
      )
      display.call
      expect(io.string).to include([
        "> 2  ",
        DisplayCodeWithLineNumbers::TERMINAL_HIGHLIGHT,
        "  def hello"
      ].join)

      io = StringIO.new
      def io.isatty
        false
      end

      block = CodeBlock.new(lines: code_lines[1])
      display = DisplayInvalidBlocks.new(
        io: io,
        blocks: block,
        code_lines: code_lines
      )
      display.call
      expect(io.string).to include("> 2    def hello")
    end

    it "outputs to io when using `call`" do
      source = <<~EOM
        class OH
          def hello
          def hai
          end
        end
      EOM

      code_lines = CleanDocument.new(source: source).call.lines

      io = StringIO.new
      block = CodeBlock.new(lines: code_lines[1])
      display = DisplayInvalidBlocks.new(
        io: io,
        blocks: block,
        terminal: false,
        code_lines: code_lines
      )
      display.call
      expect(io.string).to include("> 2    def hello")
    end

    it " wraps code with github style codeblocks" do
      source = <<~EOM
        class OH
          def hello

          def hai
          end
        end
      EOM

      code_lines = CleanDocument.new(source: source).call.lines
      block = CodeBlock.new(lines: code_lines[1])
      io = StringIO.new
      DisplayInvalidBlocks.new(
        io: io,
        blocks: block,
        terminal: false,
        code_lines: code_lines
      ).call
      expect(io.string).to include(<<~EOM)
          1  class OH
        > 2    def hello
          4    def hai
          5    end
          6  end
      EOM
    end

    it "shows terminal characters" do
      code_lines = code_line_array(<<~EOM)
        class OH
          def hello
          def hai
          end
        end
      EOM

      io = StringIO.new
      block = CodeBlock.new(lines: code_lines[1])
      DisplayInvalidBlocks.new(
        io: io,
        blocks: block,
        terminal: false,
        code_lines: code_lines
      ).call

      expect(io.string).to include([
        "  1  class OH",
        "> 2    def hello",
        "  3    def hai",
        "  4    end",
        "  5  end",
        ""
      ].join($/))

      block = CodeBlock.new(lines: code_lines[1])
      io = StringIO.new
      DisplayInvalidBlocks.new(
        io: io,
        blocks: block,
        terminal: true,
        code_lines: code_lines
      ).call

      expect(io.string).to include(
        [
          "  1  class OH",
          ["> 2  ", DisplayCodeWithLineNumbers::TERMINAL_HIGHLIGHT, "  def hello"].join,
          "  3    def hai",
          "  4    end",
          "  5  end",
          ""
        ].join($/ + DisplayCodeWithLineNumbers::TERMINAL_END)
      )
    end
  end
end
