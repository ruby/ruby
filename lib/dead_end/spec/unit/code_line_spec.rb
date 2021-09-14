# frozen_string_literal: true

require_relative "../spec_helper.rb"

module DeadEnd
  RSpec.describe CodeLine do
    it "trailing if" do
      code_lines = code_line_array(<<~'EOM')
        puts "lol" if foo
        if foo
        end
      EOM

      expect(code_lines.map(&:is_kw?)).to eq([false, true, false])
    end

    it "trailing unless" do
      code_lines = code_line_array(<<~'EOM')
        puts "lol" unless foo
        unless foo
        end
      EOM

      expect(code_lines.map(&:is_kw?)).to eq([false, true, false])
    end

    it "trailing slash" do
      code_lines = code_line_array(<<~'EOM')
        it "trailing s" \
           "lash" do
      EOM

      expect(code_lines.map(&:trailing_slash?)).to eq([true, false])

      code_lines = code_line_array(<<~'EOM')
        amazing_print: ->(obj)  { obj.ai + "\n" },
      EOM
      expect(code_lines.map(&:trailing_slash?)).to eq([false])
    end

    it "knows it's a comment" do
      line = CodeLine.new(line: "   # iama comment", index: 0)
      expect(line.is_comment?).to be_truthy
      expect(line.is_end?).to be_falsey
      expect(line.is_kw?).to be_falsey
    end

    it "knows it's got an end" do
      line = CodeLine.new(line: "   end", index: 0)

      expect(line.is_comment?).to be_falsey
      expect(line.is_end?).to be_truthy
      expect(line.is_kw?).to be_falsey
    end

    it "knows it's got a keyword" do
      line = CodeLine.new(line: "  if", index: 0)

      expect(line.is_comment?).to be_falsey
      expect(line.is_end?).to be_falsey
      expect(line.is_kw?).to be_truthy
    end

    it "ignores marked lines" do
      code_lines = code_line_array(<<~EOM)
        def foo
          Array(value) |x|
          end
        end
      EOM

      expect(DeadEnd.valid?(code_lines)).to be_falsey
      expect(code_lines.join).to eq(<<~EOM)
        def foo
          Array(value) |x|
          end
        end
      EOM

      expect(code_lines[0].visible?).to be_truthy
      expect(code_lines[3].visible?).to be_truthy

      code_lines[0].mark_invisible
      code_lines[3].mark_invisible

      expect(code_lines[0].visible?).to be_falsey
      expect(code_lines[3].visible?).to be_falsey

      expect(code_lines.join).to eq(<<~EOM.indent(2))
        Array(value) |x|
        end
      EOM
      expect(DeadEnd.valid?(code_lines)).to be_falsey
    end

    it "knows empty lines" do
      code_lines = code_line_array(<<~EOM)
        # Not empty

        # Not empty
      EOM

      expect(code_lines.map(&:empty?)).to eq([false, true, false])
      expect(code_lines.map(&:not_empty?)).to eq([true, false, true])
      expect(code_lines.map {|l| DeadEnd.valid?(l) }).to eq([true, true, true])
    end

    it "counts indentations" do
      code_lines = code_line_array(<<~EOM)
        def foo
          Array(value) |x|
            puts 'lol'
          end
        end
      EOM

      expect(code_lines.map(&:indent)).to eq([0, 2, 4, 2, 0])
    end

    it "doesn't count empty lines as having an indentation" do
      code_lines = code_line_array(<<~EOM)


      EOM

      expect(code_lines.map(&:indent)).to eq([0, 0])
    end
  end
end
