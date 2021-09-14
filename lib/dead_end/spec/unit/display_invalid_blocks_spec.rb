# frozen_string_literal: true

require_relative "../spec_helper.rb"

module DeadEnd
  RSpec.describe DisplayInvalidBlocks do
    it "Unmatched | banner" do
      source = <<~EOM
        Foo.call do |
        end
      EOM
      code_lines = code_line_array(source)

      display = DisplayInvalidBlocks.new(
        code_lines: code_lines,
        blocks: CodeBlock.new(lines: code_lines),
        invalid_obj: WhoDisSyntaxError.new(source),
      )
      expect(display.banner).to include("Unmatched `|` character detected")
    end

    it "Unmatched } banner" do
      source = <<~EOM
        class Cat
          lol = {
        end
      EOM
      code_lines = code_line_array(source)

      display = DisplayInvalidBlocks.new(
        code_lines: code_lines,
        blocks: CodeBlock.new(lines: code_lines),
        invalid_obj: WhoDisSyntaxError.new(source),
      )
      expect(display.banner).to include("Unmatched `}` character detected")
    end

    it "Unmatched end banner" do
      source = <<~EOM
        class Cat
          end
        end
      EOM
      code_lines = code_line_array(source)

      display = DisplayInvalidBlocks.new(
        code_lines: code_lines,
        blocks: CodeBlock.new(lines: code_lines),
        invalid_obj: WhoDisSyntaxError.new(source),
      )
      expect(display.banner).to include("DeadEnd: Unmatched `end` detected")
    end

    it "Unmatched unknown banner" do
      source = <<~EOM
        class Cat
          def meow
            1 *
          end
        end
      EOM
      code_lines = code_line_array(source)

      display = DisplayInvalidBlocks.new(
        code_lines: code_lines,
        blocks: CodeBlock.new(lines: code_lines),
        invalid_obj: WhoDisSyntaxError.new(source),
      )
      expect(display.banner).to include("DeadEnd: Unmatched `unknown` detected")
    end

    it "missing end banner" do
      source = <<~EOM
        class Cat
          def meow
        end
      EOM
      code_lines = code_line_array(source)

      display = DisplayInvalidBlocks.new(
        code_lines: code_lines,
        blocks: CodeBlock.new(lines: code_lines),
        invalid_obj: WhoDisSyntaxError.new(source),
      )
      expect(display.banner).to include("DeadEnd: Missing `end` detected")
    end

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
        code_lines: search.code_lines,
      )
      display.call
      expect(io.string).to include("Syntax OK")
    end

    it "outputs to io when using `call`" do
      code_lines = code_line_array(<<~EOM)
        class OH
          def hello
          def hai
          end
        end
      EOM

      io = StringIO.new
      block = CodeBlock.new(lines: code_lines[1])
      display = DisplayInvalidBlocks.new(
        io: io,
        blocks: block,
        terminal: false,
        code_lines: code_lines,
      )
      display.call
      expect(io.string).to include("❯ 2    def hello")
      expect(io.string).to include("DeadEnd")
    end

    it " wraps code with github style codeblocks" do
      code_lines = code_line_array(<<~EOM)
        class OH
          def hello

          def hai
          end
        end
      EOM

      block = CodeBlock.new(lines: code_lines[1])
      display = DisplayInvalidBlocks.new(
        blocks: block,
        terminal: false,
        code_lines: code_lines
      )
      expect(display.code_block).to eq(<<~EOM)
         1  class OH
       ❯ 2    def hello
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

      block = CodeBlock.new(lines: code_lines[1])
      display = DisplayInvalidBlocks.new(
        blocks: block,
        terminal: false,
        code_lines: code_lines
      )

      expect(display.code_with_lines).to eq(
        [
          "  1  class OH",
          "❯ 2    def hello",
          "  3    def hai",
          "  4    end",
          "  5  end",
          ""
        ].join($/)
      )

      block = CodeBlock.new(lines: code_lines[1])
      display = DisplayInvalidBlocks.new(
        blocks: block,
        terminal: true,
        code_lines: code_lines
      )

      expect(display.code_with_lines).to eq(
        [
          "  1  class OH",
         ["❯ 2  ", DisplayCodeWithLineNumbers::TERMINAL_HIGHLIGHT, "  def hello"].join,
          "  3    def hai",
          "  4    end",
          "  5  end",
          ""
        ].join($/ + DisplayCodeWithLineNumbers::TERMINAL_END)
      )
    end
  end
end
