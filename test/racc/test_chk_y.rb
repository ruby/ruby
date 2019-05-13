require File.expand_path(File.join(File.dirname(__FILE__), 'helper'))

module Racc
  class TestChkY < TestCase
    def setup
      file = File.join(ASSET_DIR, 'chk.y')
      @debug_flags = Racc::DebugFlags.parse_option_string('o')
      parser = Racc::GrammarFileParser.new(@debug_flags)
      @result = parser.parse(File.read(file), File.basename(file))
      @states = Racc::States.new(@result.grammar).nfa
      @states.dfa
    end

    def test_compile_chk_y
      generator = Racc::ParserFileGenerator.new(@states, @result.params.dup)

      # it generates valid ruby
      assert Module.new {
        self.instance_eval(generator.generate_parser, __FILE__, __LINE__)
      }

      grammar = @states.grammar

      assert_equal 0, @states.n_srconflicts
      assert_equal 0, @states.n_rrconflicts
      assert_equal 0, grammar.n_useless_nonterminals
      assert_equal 0, grammar.n_useless_rules
      assert_nil grammar.n_expected_srconflicts
    end

    def test_compile_chk_y_line_convert
      params = @result.params.dup
      params.convert_line_all = true

      generator = Racc::ParserFileGenerator.new(@states, @result.params.dup)

      # it generates valid ruby
      assert Module.new {
        self.instance_eval(generator.generate_parser, __FILE__, __LINE__)
      }

      grammar = @states.grammar

      assert_equal 0, @states.n_srconflicts
      assert_equal 0, @states.n_rrconflicts
      assert_equal 0, grammar.n_useless_nonterminals
      assert_equal 0, grammar.n_useless_rules
      assert_nil grammar.n_expected_srconflicts
    end
  end
end
