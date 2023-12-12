# frozen_string_literal: true
require "irb"

require_relative "helper"

module TestIRB
  class EvalHistoryTest < TestCase
    def setup
      save_encodings
      IRB.instance_variable_get(:@CONF).clear
    end

    def teardown
      restore_encodings
    end

    def execute_lines(*lines, conf: {}, main: self, irb_path: nil)
      IRB.init_config(nil)
      IRB.conf[:VERBOSE] = false
      IRB.conf[:PROMPT_MODE] = :SIMPLE
      IRB.conf[:USE_PAGER] = false
      IRB.conf.merge!(conf)
      input = TestInputMethod.new(lines)
      irb = IRB::Irb.new(IRB::WorkSpace.new(main), input)
      irb.context.return_format = "=> %s\n"
      irb.context.irb_path = irb_path if irb_path
      IRB.conf[:MAIN_CONTEXT] = irb.context
      capture_output do
        irb.eval_input
      end
    end

    def test_eval_history_is_diabled_by_default
      out, err = execute_lines(
        "a = 1",
        "__"
      )

      assert_empty(err)
      assert_match(/undefined local variable or method `__'/, out)
    end

    def test_eval_history_can_be_retrieved_with_double_underscore
      out, err = execute_lines(
        "a = 1",
        "__",
        conf: { EVAL_HISTORY: 5 }
      )

      assert_empty(err)
      assert_match("=> 1\n" + "=> 1 1\n", out)
    end

    def test_eval_history_respects_given_limit
      out, err = execute_lines(
        "'foo'\n",
        "'bar'\n",
        "'baz'\n",
        "'xyz'\n",
        "__",
        conf: { EVAL_HISTORY: 4 }
      )

      assert_empty(err)
      # Because eval_history injects `__` into the history AND decide to ignore it, we only get <limit> - 1 results
      assert_match("2 \"bar\"\n" + "3 \"baz\"\n" + "4 \"xyz\"\n", out)
    end
  end
end
