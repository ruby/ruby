# frozen_string_literal: true

require_relative "../spec_helper"

module SyntaxSuggest
  RSpec.describe CodeLine do
    it "bug in keyword detection" do
      lines = CodeLine.from_source(<<~'EOM')
        def to_json(*opts)
          {
            type: :module,
          }.to_json(*opts)
        end
      EOM
      expect(lines.count(&:is_kw?)).to eq(1)
      expect(lines.count(&:is_end?)).to eq(1)
    end

    it "supports endless method definitions" do
      skip("Unsupported ruby version") unless Gem::Version.new(RUBY_VERSION) >= Gem::Version.new("3")

      line = CodeLine.from_source(<<~'EOM').first
        def square(x) = x * x
      EOM

      expect(line.is_kw?).to be_falsey
      expect(line.is_end?).to be_falsey
    end

    it "retains original line value, after being marked invisible" do
      line = CodeLine.from_source(<<~'EOM').first
        puts "lol"
      EOM
      expect(line.line).to match('puts "lol"')
      line.mark_invisible
      expect(line.line).to eq("")
      expect(line.original).to match('puts "lol"')
    end

    it "knows which lines can be joined" do
      code_lines = CodeLine.from_source(<<~'EOM')
        user = User.
          where(name: 'schneems').
          first
        puts user.name
      EOM

      # Indicates line 1 can join 2, 2 can join 3, but 3 won't join it's next line
      expect(code_lines.map(&:ignore_newline_not_beg?)).to eq([true, true, false, false])
    end

    it "trailing if" do
      code_lines = CodeLine.from_source(<<~'EOM')
        puts "lol" if foo
        if foo
        end
      EOM

      expect(code_lines.map(&:is_kw?)).to eq([false, true, false])
    end

    it "trailing unless" do
      code_lines = CodeLine.from_source(<<~'EOM')
        puts "lol" unless foo
        unless foo
        end
      EOM

      expect(code_lines.map(&:is_kw?)).to eq([false, true, false])
    end

    it "trailing slash" do
      code_lines = CodeLine.from_source(<<~'EOM')
        it "trailing s" \
           "lash" do
      EOM

      expect(code_lines.map(&:trailing_slash?)).to eq([true, false])

      code_lines = CodeLine.from_source(<<~'EOM')
        amazing_print: ->(obj)  { obj.ai + "\n" },
      EOM
      expect(code_lines.map(&:trailing_slash?)).to eq([false])
    end

    it "knows it's got an end" do
      line = CodeLine.from_source("   end").first

      expect(line.is_end?).to be_truthy
      expect(line.is_kw?).to be_falsey
    end

    it "knows it's got a keyword" do
      line = CodeLine.from_source("  if").first

      expect(line.is_end?).to be_falsey
      expect(line.is_kw?).to be_truthy
    end

    it "ignores marked lines" do
      code_lines = CodeLine.from_source(<<~EOM)
        def foo
          Array(value) |x|
          end
        end
      EOM

      expect(SyntaxSuggest.valid?(code_lines)).to be_falsey
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
      expect(SyntaxSuggest.valid?(code_lines)).to be_falsey
    end

    it "knows empty lines" do
      code_lines = CodeLine.from_source(<<~EOM)
        # Not empty

        # Not empty
      EOM

      expect(code_lines.map(&:empty?)).to eq([false, true, false])
      expect(code_lines.map(&:not_empty?)).to eq([true, false, true])
      expect(code_lines.map { |l| SyntaxSuggest.valid?(l) }).to eq([true, true, true])
    end

    it "counts indentations" do
      code_lines = CodeLine.from_source(<<~EOM)
        def foo
          Array(value) |x|
            puts 'lol'
          end
        end
      EOM

      expect(code_lines.map(&:indent)).to eq([0, 2, 4, 2, 0])
    end

    it "doesn't count empty lines as having an indentation" do
      code_lines = CodeLine.from_source(<<~EOM)


      EOM

      expect(code_lines.map(&:indent)).to eq([0, 0])
    end
  end
end
