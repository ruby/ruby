# frozen_string_literal: true

require_relative "../spec_helper"

module SyntaxSuggest
  RSpec.describe BlockExpand do
    it "captures multiple empty and hidden lines" do
      source_string = <<~EOM
        def foo
          Foo.call


            puts "lol"

            # hidden
          end
        end
      EOM

      code_lines = code_line_array(source_string)

      code_lines[6].mark_invisible

      block = CodeBlock.new(lines: [code_lines[3]])
      expansion = BlockExpand.new(code_lines: code_lines)
      block = expansion.call(block)

      expect(block.to_s).to eq(<<~EOM.indent(4))


        puts "lol"

      EOM
    end

    it "captures multiple empty lines" do
      source_string = <<~EOM
        def foo
          Foo.call


            puts "lol"

          end
        end
      EOM

      code_lines = code_line_array(source_string)
      block = CodeBlock.new(lines: [code_lines[3]])
      expansion = BlockExpand.new(code_lines: code_lines)
      block = expansion.call(block)

      expect(block.to_s).to eq(<<~EOM.indent(4))


        puts "lol"

      EOM
    end

    it "expands neighbors then indentation" do
      source_string = <<~EOM
        def foo
          Foo.call
            puts "hey"
            puts "lol"
            puts "sup"
          end
        end
      EOM

      code_lines = code_line_array(source_string)
      block = CodeBlock.new(lines: [code_lines[3]])
      expansion = BlockExpand.new(code_lines: code_lines)
      block = expansion.call(block)

      expect(block.to_s).to eq(<<~EOM.indent(4))
        puts "hey"
        puts "lol"
        puts "sup"
      EOM

      block = expansion.call(block)

      expect(block.to_s).to eq(<<~EOM.indent(2))
        Foo.call
          puts "hey"
          puts "lol"
          puts "sup"
        end
      EOM
    end

    it "handles else code" do
      source_string = <<~EOM
        Foo.call
          if blerg
            puts "lol"
          else
            puts "haha"
          end
        end
      EOM

      code_lines = code_line_array(source_string)
      block = CodeBlock.new(lines: [code_lines[2]])
      expansion = BlockExpand.new(code_lines: code_lines)
      block = expansion.call(block)

      expect(block.to_s).to eq(<<~EOM.indent(2))
        if blerg
          puts "lol"
        else
          puts "haha"
        end
      EOM
    end

    it "expand until next boundry (indentation)" do
      source_string = <<~EOM
        describe "what" do
          Foo.call
        end

        describe "hi"
          Bar.call do
            Foo.call
          end
        end

        it "blerg" do
        end
      EOM

      code_lines = code_line_array(source_string)

      block = CodeBlock.new(
        lines: code_lines[6]
      )

      expansion = BlockExpand.new(code_lines: code_lines)
      block = expansion.call(block)

      expect(block.to_s).to eq(<<~EOM.indent(2))
        Bar.call do
          Foo.call
        end
      EOM

      block = expansion.call(block)

      expect(block.to_s).to eq(<<~EOM)
        describe "hi"
          Bar.call do
            Foo.call
          end
        end
      EOM
    end

    it "expand until next boundry (empty lines)" do
      source_string = <<~EOM
        describe "what" do
        end

        describe "hi"
        end

        it "blerg" do
        end
      EOM

      code_lines = code_line_array(source_string)
      expansion = BlockExpand.new(code_lines: code_lines)

      block = CodeBlock.new(lines: code_lines[3])
      block = expansion.call(block)

      expect(block.to_s).to eq(<<~EOM)

        describe "hi"
        end

      EOM

      block = expansion.call(block)

      expect(block.to_s).to eq(<<~EOM)
        describe "what" do
        end

        describe "hi"
        end

        it "blerg" do
        end
      EOM
    end
  end
end
