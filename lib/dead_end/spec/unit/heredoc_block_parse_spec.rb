# frozen_string_literal: true

require_relative "../spec_helper.rb"

module DeadEnd

  RSpec.describe "HeredocBlockParse" do
    it "works" do
      source = fixtures_dir.join("this_project_extra_def.rb.txt").read
      code_lines = code_line_array(source)
      blocks = HeredocBlockParse.new(source: source, code_lines: code_lines).call
      expect(blocks[0].to_s).to eq(<<-'EOL')
      @io.puts <<~EOM

        DeadEnd: A syntax error was detected

        This code has an unmatched `end` this is caused by either
        missing a syntax keyword (`def`,  `do`, etc.) or inclusion
        of an extra `end` line:
      EOM
      EOL

      expect(blocks[1].to_s).to eq(<<-'EOL')
      @io.puts(<<~EOM) if filename
        file: #{filename}
      EOM
      EOL

      expect(blocks[2].to_s).to eq(<<-'EOL')
      @io.puts <<~EOM
        #{code_with_filename}
      EOM
      EOL

      expect(blocks[3]).to be_nil
    end
  end
end
