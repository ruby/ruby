# frozen_string_literal: true
require "irb"

require_relative "helper"

module TestIRB
  class HelperMethodTestCase < TestCase
    def setup
      $VERBOSE = nil
      @verbosity = $VERBOSE
      save_encodings
      IRB.instance_variable_get(:@CONF).clear
    end

    def teardown
      $VERBOSE = @verbosity
      restore_encodings
    end

    def execute_lines(*lines, conf: {}, main: self, irb_path: nil)
      IRB.init_config(nil)
      IRB.conf[:VERBOSE] = false
      IRB.conf[:PROMPT_MODE] = :SIMPLE
      IRB.conf.merge!(conf)
      input = TestInputMethod.new(lines)
      irb = IRB::Irb.new(IRB::WorkSpace.new(main), input)
      irb.context.return_format = "=> %s\n"
      irb.context.irb_path = irb_path if irb_path
      IRB.conf[:MAIN_CONTEXT] = irb.context
      IRB.conf[:USE_PAGER] = false
      capture_output do
        irb.eval_input
      end
    end
  end

  module TestHelperMethod
    class ConfTest < HelperMethodTestCase
      def test_conf_returns_the_context_object
        out, err = execute_lines("conf.ap_name")

        assert_empty err
        assert_include out, "=> \"irb\""
      end
    end
  end

  class HelperMethodIntegrationTest < IntegrationTestCase
    def test_arguments_propogation
      write_ruby <<~RUBY
        require "irb/helper_method"

        class MyHelper < IRB::HelperMethod::Base
          description "This is a test helper"

          def execute(
            required_arg, optional_arg = nil, *splat_arg, required_keyword_arg:,
            optional_keyword_arg: nil, **double_splat_arg, &block_arg
          )
            puts [required_arg, optional_arg, splat_arg, required_keyword_arg, optional_keyword_arg, double_splat_arg, block_arg.call].to_s
          end
        end

        IRB::HelperMethod.register(:my_helper, MyHelper)

        binding.irb
      RUBY

      output = run_ruby_file do
        type <<~INPUT
          my_helper(
            "required", "optional", "splat", required_keyword_arg: "required",
            optional_keyword_arg: "optional", a: 1, b: 2
          ) { "block" }
        INPUT
        type "exit"
      end

      assert_include(output, '["required", "optional", ["splat"], "required", "optional", {:a=>1, :b=>2}, "block"]')
    end

    def test_helper_method_injection_can_happen_after_irb_require
      write_ruby <<~RUBY
        require "irb"

        class MyHelper < IRB::HelperMethod::Base
          description "This is a test helper"

          def execute
            puts "Hello from MyHelper"
          end
        end

        IRB::HelperMethod.register(:my_helper, MyHelper)

        binding.irb
      RUBY

      output = run_ruby_file do
        type <<~INPUT
          my_helper
        INPUT
        type "exit"
      end

      assert_include(output, 'Hello from MyHelper')
    end
  end
end
