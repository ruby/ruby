# frozen_string_literal: false
require "test/unit"
require "irb"

module TestIRB
  class TestCompletion < Test::Unit::TestCase
    def test_nonstring_module_name
      begin
        require "irb/completion"
        bug5938 = '[ruby-core:42244]'
        bundle_exec = ENV.key?('BUNDLE_GEMFILE') ? ['-rbundler/setup'] : []
        cmds = bundle_exec + %W[-W0 -rirb -rirb/completion -e IRB.setup(__FILE__)
         -e IRB.conf[:MAIN_CONTEXT]=IRB::Irb.new.context
         -e module\sFoo;def\sself.name;//;end;end
         -e IRB::InputCompletor::CompletionProc.call("[1].first.")
         -- -f --]
        status = assert_in_out_err(cmds, "", //, [], bug5938)
        assert(status.success?, bug5938)
      rescue LoadError
        pend "cannot load irb/completion"
      end
    end

    def test_complete_numeric
      assert_include(IRB::InputCompletor.retrieve_completion_data("1r.positi", bind: binding), "1r.positive?")
      assert_empty(IRB::InputCompletor.retrieve_completion_data("1i.positi", bind: binding))
    end

    def test_complete_symbol
      %w"UTF-16LE UTF-7".each do |enc|
        "K".force_encoding(enc).to_sym
      rescue
      end
      _ = :aiueo
      assert_include(IRB::InputCompletor.retrieve_completion_data(":a", bind: binding), ":aiueo")
      assert_empty(IRB::InputCompletor.retrieve_completion_data(":irb_unknown_symbol_abcdefg", bind: binding))
    end

    def test_complete_invalid_three_colons
      assert_empty(IRB::InputCompletor.retrieve_completion_data(":::A", bind: binding))
      assert_empty(IRB::InputCompletor.retrieve_completion_data(":::", bind: binding))
    end

    def test_complete_absolute_constants_with_special_characters
      assert_empty(IRB::InputCompletor.retrieve_completion_data("::A:", bind: binding))
      assert_empty(IRB::InputCompletor.retrieve_completion_data("::A.", bind: binding))
      assert_empty(IRB::InputCompletor.retrieve_completion_data("::A(", bind: binding))
      assert_empty(IRB::InputCompletor.retrieve_completion_data("::A)", bind: binding))
    end

    def test_complete_symbol_failure
      assert_nil(IRB::InputCompletor::PerfectMatchedProc.(":aiueo", bind: binding))
    end

    def test_complete_reserved_words
      candidates = IRB::InputCompletor.retrieve_completion_data("de", bind: binding)
      %w[def defined?].each do |word|
        assert_include candidates, word
      end

      candidates = IRB::InputCompletor.retrieve_completion_data("__", bind: binding)
      %w[__ENCODING__ __LINE__ __FILE__].each do |word|
        assert_include candidates, word
      end
    end

    def test_complete_predicate?
      candidates = IRB::InputCompletor.retrieve_completion_data("1.posi", bind: binding)
      assert_include candidates, '1.positive?'

      namespace = IRB::InputCompletor.retrieve_completion_data("1.positive?", bind: binding, doc_namespace: true)
      assert_equal "Integer.positive?", namespace
    end

    def test_complete_require
      candidates = IRB::InputCompletor::CompletionProc.("'irb", "require ", "")
      %w['irb/init 'irb/ruby-lex].each do |word|
        assert_include candidates, word
      end
      # Test cache
      candidates = IRB::InputCompletor::CompletionProc.("'irb", "require ", "")
      %w['irb/init 'irb/ruby-lex].each do |word|
        assert_include candidates, word
      end
    end

    def test_complete_require_library_name_first
      pend 'Need to use virtual library paths'
      candidates = IRB::InputCompletor::CompletionProc.("'csv", "require ", "")
      assert_equal "'csv", candidates.first
    end

    def test_complete_require_relative
      candidates = Dir.chdir(__dir__ + "/../..") do
        IRB::InputCompletor::CompletionProc.("'lib/irb", "require_relative ", "")
      end
      %w['lib/irb/init 'lib/irb/ruby-lex].each do |word|
        assert_include candidates, word
      end
      # Test cache
      candidates = Dir.chdir(__dir__ + "/../..") do
        IRB::InputCompletor::CompletionProc.("'lib/irb", "require_relative ", "")
      end
      %w['lib/irb/init 'lib/irb/ruby-lex].each do |word|
        assert_include candidates, word
      end
    end

    def test_complete_variable
      str_example = ''
      str_example.clear # suppress "assigned but unused variable" warning
      assert_include(IRB::InputCompletor.retrieve_completion_data("str_examp", bind: binding), "str_example")
      assert_equal(IRB::InputCompletor.retrieve_completion_data("str_example", bind: binding, doc_namespace: true), "String")
      assert_equal(IRB::InputCompletor.retrieve_completion_data("str_example.to_s", bind: binding, doc_namespace: true), "String.to_s")
    end

    def test_complete_class_method
      assert_include(IRB::InputCompletor.retrieve_completion_data("String.new", bind: binding), "String.new")
      assert_equal(IRB::InputCompletor.retrieve_completion_data("String.new", bind: binding, doc_namespace: true), "String.new")
    end
  end
end
