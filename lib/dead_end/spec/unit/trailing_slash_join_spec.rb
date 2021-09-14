# frozen_string_literal: true

require_relative "../spec_helper.rb"

module DeadEnd
  RSpec.describe TrailingSlashJoin do

    it "formats output" do
      code_lines = code_line_array(<<~'EOM')
        context "timezones workaround" do
          it "should receive a time in UTC format and return the time with the"\
            "office's UTC offset substracted from it" do
            travel_to DateTime.new(2020, 10, 1, 10, 0, 0) do
              office = build(:office)
            end
          end
        end
      EOM

      out_code_lines = TrailingSlashJoin.new(code_lines: code_lines).call
      expect(
        DisplayCodeWithLineNumbers.new(
          lines: out_code_lines.select(&:visible?)
        ).call
      ).to eq(<<~'EOM'.indent(2))
         1  context "timezones workaround" do
         2    it "should receive a time in UTC format and return the time with the"\
         3      "office's UTC offset substracted from it" do
         4      travel_to DateTime.new(2020, 10, 1, 10, 0, 0) do
         5        office = build(:office)
         6      end
         7    end
         8  end
      EOM

      expect(
        DisplayCodeWithLineNumbers.new(
          lines: out_code_lines.select(&:visible?),
          highlight_lines: out_code_lines[1]
        ).call
      ).to eq(<<~'EOM')
          1  context "timezones workaround" do
        ❯ 2    it "should receive a time in UTC format and return the time with the"\
        ❯ 3      "office's UTC offset substracted from it" do
          4      travel_to DateTime.new(2020, 10, 1, 10, 0, 0) do
          5        office = build(:office)
          6      end
          7    end
          8  end
      EOM
    end

    it "trailing slash" do
      code_lines = code_line_array(<<~'EOM')
        it "trailing s" \
           "lash" do
      EOM

      out_code_lines = TrailingSlashJoin.new(code_lines: code_lines).call

      expect(code_lines[0]).to_not be_hidden
      expect(code_lines[1]).to be_hidden

      expect(
        out_code_lines.join
      ).to eq(code_lines.map(&:original).join)
    end

    it "doesn't falsely identify trailing slashes" do
      code_lines = code_line_array(<<~'EOM')
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

      out_code_lines = TrailingSlashJoin.new(code_lines: code_lines).call
      expect(out_code_lines.join).to eq(code_lines.join)
    end
  end
end
