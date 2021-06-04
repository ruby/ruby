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
        skip "cannot load irb/completion"
      end
    end

    def test_complete_numeric
      assert_include(IRB::InputCompletor.retrieve_completion_data("1r.positi", bind: binding), "1r.positive?")
      assert_empty(IRB::InputCompletor.retrieve_completion_data("1i.positi", bind: binding))
    end

    def test_complete_symbol
      _ = :aiueo
      assert_include(IRB::InputCompletor.retrieve_completion_data(":a", bind: binding), ":aiueo")
      assert_empty(IRB::InputCompletor.retrieve_completion_data(":irb_unknown_symbol_abcdefg", bind: binding))
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
  end
end
