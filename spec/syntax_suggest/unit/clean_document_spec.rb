# frozen_string_literal: true

require_relative "../spec_helper"

module SyntaxSuggest
  RSpec.describe CleanDocument do
    it "heredocs" do
      source = fixtures_dir.join("this_project_extra_def.rb.txt").read
      code_lines = CleanDocument.new(source: source).call.lines

      expect(code_lines[18 - 1].to_s).to eq(<<-EOL)
      @io.puts <<~EOM

        SyntaxSuggest: A syntax error was detected

        This code has an unmatched `end` this is caused by either
        missing a syntax keyword (`def`,  `do`, etc.) or inclusion
        of an extra `end` line:
      EOM
      EOL
      expect(code_lines[18].to_s).to eq("")

      expect(code_lines[27 - 1].to_s).to eq(<<-'EOL')
      @io.puts(<<~EOM) if filename
        file: #{filename}
      EOM
      EOL
      expect(code_lines[27].to_s).to eq("")

      expect(code_lines[31 - 1].to_s).to eq(<<-'EOL')
      @io.puts <<~EOM
        #{code_with_filename}
      EOM
      EOL
      expect(code_lines[31].to_s).to eq("")
    end

    it "joins: multi line methods" do
      source = <<~EOM
        User
          .where(name: 'schneems')
          .first
      EOM

      doc = CleanDocument.new(source: source).join_consecutive!

      expect(doc.lines[0].to_s).to eq(source)
      expect(doc.lines[1].to_s).to eq("")
      expect(doc.lines[2].to_s).to eq("")
      expect(doc.lines[3]).to eq(nil)

      lines = doc.lines
      expect(
        DisplayCodeWithLineNumbers.new(
          lines: lines
        ).call
      ).to eq(<<~EOM.indent(2))
        1  User
        2    .where(name: 'schneems')
        3    .first
      EOM

      expect(
        DisplayCodeWithLineNumbers.new(
          lines: lines,
          highlight_lines: lines[0]
        ).call
      ).to eq(<<~EOM)
        > 1  User
        > 2    .where(name: 'schneems')
        > 3    .first
      EOM
    end

    it "joins multi-line chained methods when separated by comments" do
      source = <<~EOM
        User.
          # comment
          where(name: 'schneems').
          # another comment
          first
      EOM

      doc = CleanDocument.new(source: source).join_consecutive!
      code_lines = doc.lines

      expect(code_lines[0].to_s.count($/)).to eq(5)
      code_lines[1..].each do |line|
        expect(line.to_s.strip.length).to eq(0)
      end
    end

    it "helper method: take_while_including" do
      source = <<~EOM
        User
          .where(name: 'schneems')
          .first
      EOM

      doc = CleanDocument.new(source: source)

      lines = doc.take_while_including { |line| !line.to_s.include?("where") }
      expect(lines.count).to eq(2)
    end

    it "comments: removes comments" do
      source = <<~EOM
        # lol
        puts "what"
          # yolo
      EOM

      lines = CleanDocument.new(source: source).lines
      expect(lines[0].to_s).to eq($/)
      expect(lines[1].to_s).to eq('puts "what"' + $/)
      expect(lines[2].to_s).to eq($/)
    end

    it "trailing slash: does not join trailing do" do
      # Some keywords and syntaxes trigger the "ignored line"
      # lex output, we ignore them by filtering by BEG
      #
      # The `do` keyword is one of these:
      # https://gist.github.com/schneems/6a7d7f988d3329fb3bd4b5be3e2efc0c
      source = <<~EOM
        foo do
          puts "lol"
        end
      EOM

      doc = CleanDocument.new(source: source).join_consecutive!

      expect(doc.lines[0].to_s).to eq(source.lines[0])
      expect(doc.lines[1].to_s).to eq(source.lines[1])
      expect(doc.lines[2].to_s).to eq(source.lines[2])
    end

    it "trailing slash: formats output" do
      source = <<~'EOM'
        context "timezones workaround" do
          it "should receive a time in UTC format and return the time with the"\
            "office's UTC offset subtracted from it" do
            travel_to DateTime.new(2020, 10, 1, 10, 0, 0) do
              office = build(:office)
            end
          end
        end
      EOM

      code_lines = CleanDocument.new(source: source).call.lines
      expect(
        DisplayCodeWithLineNumbers.new(
          lines: code_lines.select(&:visible?)
        ).call
      ).to eq(<<~'EOM'.indent(2))
        1  context "timezones workaround" do
        2    it "should receive a time in UTC format and return the time with the"\
        3      "office's UTC offset subtracted from it" do
        4      travel_to DateTime.new(2020, 10, 1, 10, 0, 0) do
        5        office = build(:office)
        6      end
        7    end
        8  end
      EOM

      expect(
        DisplayCodeWithLineNumbers.new(
          lines: code_lines.select(&:visible?),
          highlight_lines: code_lines[1]
        ).call
      ).to eq(<<~'EOM')
          1  context "timezones workaround" do
        > 2    it "should receive a time in UTC format and return the time with the"\
        > 3      "office's UTC offset subtracted from it" do
          4      travel_to DateTime.new(2020, 10, 1, 10, 0, 0) do
          5        office = build(:office)
          6      end
          7    end
          8  end
      EOM
    end

    it "trailing slash: basic detection" do
      source = <<~'EOM'
        it "trailing s" \
           "lash" do
      EOM

      code_lines = CleanDocument.new(source: source).call.lines

      expect(code_lines[0]).to_not be_hidden
      expect(code_lines[1]).to be_hidden

      expect(
        code_lines.join
      ).to eq(code_lines.map(&:original).join)
    end

    it "trailing slash: joins multiple lines" do
      source = <<~'EOM'
        it "should " \
           "keep " \
           "going " do
        end
      EOM

      doc = CleanDocument.new(source: source).join_trailing_slash!
      expect(doc.lines[0].to_s).to eq(source.lines[0..2].join)
      expect(doc.lines[1].to_s).to eq("")
      expect(doc.lines[2].to_s).to eq("")
      expect(doc.lines[3].to_s).to eq(source.lines[3])

      lines = doc.lines
      expect(
        DisplayCodeWithLineNumbers.new(
          lines: lines
        ).call
      ).to eq(<<~'EOM'.indent(2))
        1  it "should " \
        2     "keep " \
        3     "going " do
        4  end
      EOM

      expect(
        DisplayCodeWithLineNumbers.new(
          lines: lines,
          highlight_lines: lines[0]
        ).call
      ).to eq(<<~'EOM')
        > 1  it "should " \
        > 2     "keep " \
        > 3     "going " do
          4  end
      EOM
    end

    it "trailing slash: no false positives" do
      source = <<~'EOM'
        def formatters
          @formatters ||=  {
              amazing_print: ->(obj)  { obj.ai + "\n" },
              inspect:       ->(obj)  { obj.inspect + "\n" },
              json:          ->(obj)  { obj.to_json },
              marshal:       ->(obj)  { Marshal.dump(obj) },
              none:          ->(_obj) { nil },
              pretty_json:   ->(obj)  { JSON.pretty_generate(obj) },
              pretty_print:  ->(obj)  { obj.pretty_inspect },
              puts:          ->(obj)  { require 'stringio'; sio = StringIO.new; sio.puts(obj); sio.string },
              to_s:          ->(obj)  { obj.to_s + "\n" },
              yaml:          ->(obj)  { obj.to_yaml },
          }
        end
      EOM

      code_lines = CleanDocument.new(source: source).call.lines
      expect(code_lines.join).to eq(code_lines.join)
    end
  end
end
