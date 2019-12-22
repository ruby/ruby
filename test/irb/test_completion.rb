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
  end
end
