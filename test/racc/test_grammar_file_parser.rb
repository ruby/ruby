require File.expand_path(File.join(__dir__, 'case'))

module Racc
  class TestGrammarFileParser < TestCase
    def test_parse
      file = File.join(ASSET_DIR, 'yyerr.y')

      debug_flags = Racc::DebugFlags.parse_option_string('o')
      assert debug_flags.status_logging

      parser = Racc::GrammarFileParser.new(debug_flags)
      parser.parse(File.read(file), File.basename(file))
    end
  end
end
