# frozen_string_literal: false
require 'test/unit'
require 'irb/ruby-lex'
require 'stringio'

module TestIRB
  class TestRubyLex < Test::Unit::TestCase
    def setup
      @scanner = RubyLex.new
    end

    def teardown
      RubyLex.debug_level = 0
    end

    def test_set_input_proc
      called = false
      @scanner.set_input(nil) {called = true; nil}
      @scanner.each_top_level_statement {}
      assert(called)
    end

    def test_comment
      assert_equal([["#\n", 1]], top_level_statement("#\n"))
    end

    def test_top_level_statement
      result = top_level_statement("#{<<-"begin;"}#{<<~"end;"}")
      begin;
        begin
        end
        begin
        end
      end;
      assert_equal([
                     ["begin\n""end\n", 1],
                     ["begin\n""end\n", 3],
                   ],
                   result)
    end

    def test_immature_statement
      src = "if false\n"
      assert_equal([[src, 1]], top_level_statement(src))
    end

    def test_prompt
      prompts = []
      @scanner.set_prompt {|*a|
        a << @scanner.instance_variable_get(:@lex_state)
        unless prompts.last == a
          prompts << a
        end
      }
      src, lineno = "#{<<-"begin;"}#{<<~'end;'}", __LINE__+1
      begin;
        #            #;# LTYPE:INDENT:CONTINUE
        x            #;# -:0:-
        x(           #;# -:0:-
        )            #;# -:1:*
        a \          #;# -:0:-
                     #;# -:0:*
        a;           #;# -:0:-
        a            #;# -:0:-
                     #;# -:0:-
        a            #;# -:0:-
        a =          #;# -:0:-
          '          #;# -:0:*
          '          #;# ':0:*
        if false or  #;# -:0:-
          true       #;# -:1:*
          a          #;# -:1:-
          "          #;# -:1:-
          "          #;# ":1:-
          begin      #;# -:1:-
            a        #;# -:2:-
            a        #;# -:2:-
          end        #;# -:2:-
        else         #;# -:1:-
          nil        #;# -:1:-
        end          #;# -:1:-
      end;
      top_level_statement(src.gsub(/[ \t]*#;#.*/, ''))
      src.each_line.with_index(1) do |line, i|
        p = prompts.shift
        next unless /#;#\s*(?:-|(?<ltype>\S)):(?<indent>\d+):(?:(?<cont>\*)|-)(?:.*FIXME:(?<fixme>.*))?/ =~ line
        indent = indent.to_i
        cont = (fixme && /`continue'/.match?(fixme)) ^ cont
        assert_equal([ltype, indent, cont, i], p[0..3], "#{lineno+i}:#{p[4]}: #{line}")
      end
    end

    def top_level_statement(lines)
      input = InputLines.new(lines, "r")
      scanned = []
      @scanner.set_input(input)
      @scanner.each_top_level_statement {|*e|
        scanned << e
        yield(*e) if defined?(yield)
      }
      scanned
    end

    class InputLines < StringIO
      alias encoding external_encoding
    end
  end
end
