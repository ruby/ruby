# frozen_string_literal: true

return if RUBY_ENGINE == "ruby" && RUBY_VERSION < "3.4"
return if defined?(RubyVM::InstructionSequence) && RubyVM::InstructionSequence.compile("").to_a[4][:parser] != :prism

require_relative "../test_helper"
require_relative "find_fixtures"

module Prism
  class FindTest < TestCase
    Fixtures = FindFixtures
    FIXTURES_PATH = File.expand_path("find_fixtures.rb", __dir__)

    # === Method / UnboundMethod tests ===

    def test_simple_method
      assert_def_node Prism.find(Fixtures::Methods.instance_method(:simple_method)), :simple_method
    end

    def test_method_with_params
      node = Prism.find(Fixtures::Methods.instance_method(:method_with_params))
      assert_def_node node, :method_with_params
      assert_equal 3, node.parameters.requireds.length
    end

    def test_method_with_block_param
      assert_def_node Prism.find(Fixtures::Methods.instance_method(:method_with_block)), :method_with_block
    end

    def test_singleton_method
      assert_def_node Prism.find(Fixtures::Methods.method(:singleton_method_fixture)), :singleton_method_fixture
    end

    def test_utf8_method_name
      assert_def_node Prism.find(Fixtures::Methods.instance_method(:été)), :été
    end

    def test_inline_method
      assert_def_node Prism.find(Fixtures::Methods.instance_method(:inline_method)), :inline_method
    end

    def test_bound_method
      obj = Object.new
      obj.extend(Fixtures::Methods)
      assert_def_node Prism.find(obj.method(:simple_method)), :simple_method
    end

    # === Proc / Lambda tests ===

    def test_simple_proc
      assert_not_nil Prism.find(Fixtures::Procs::SIMPLE_PROC)
    end

    def test_simple_lambda
      assert_not_nil Prism.find(Fixtures::Procs::SIMPLE_LAMBDA)
    end

    def test_multi_line_lambda
      assert_not_nil Prism.find(Fixtures::Procs::MULTI_LINE_LAMBDA)
    end

    def test_do_block_proc
      assert_not_nil Prism.find(Fixtures::Procs::DO_BLOCK_PROC)
    end

    # === define_method tests ===

    def test_define_method
      assert_not_nil Prism.find(Fixtures::DefineMethod.instance_method(:dynamic))
    end

    def test_define_method_bound
      obj = Object.new
      obj.extend(Fixtures::DefineMethod)
      assert_not_nil Prism.find(obj.method(:dynamic))
    end

    # === for loop test ===

    def test_for_loop_proc
      node = Prism.find(Fixtures::ForLoop::FOR_PROC)
      assert_instance_of ForNode, node
    end

    # === Thread::Backtrace::Location tests ===

    def test_backtrace_location_zero_division
      location = zero_division_location
      assert_not_nil location, "could not find backtrace location in fixtures file"
      assert_not_nil Prism.find(location)
    end

    def test_backtrace_location_name_error
      location = begin
        Fixtures::Errors.call_undefined
      rescue NameError => e
        fixture_backtrace_location(e)
      end

      assert_not_nil location, "could not find backtrace location in fixtures file"
      assert_not_nil Prism.find(location)
    end

    def test_backtrace_location_from_caller
      # caller_locations returns locations for the current call stack
      location = caller_locations(0, 1).first
      node = Prism.find(location)
      assert_not_nil node
    end

    def test_backtrace_location_eval_returns_nil
      location = begin
        eval("raise 'eval error'")
      rescue RuntimeError => e
        e.backtrace_locations.find { |loc| loc.path == "(eval)" || loc.label&.include?("eval") }
      end

      # eval locations have no file on disk
      assert_nil Prism.find(location) if location
    end

    # === Edge cases ===

    def test_nil_source_location
      # Built-in methods have nil source_location
      assert_nil Prism.find(method(:puts))
    end

    def test_argument_error_on_wrong_type
      assert_raise(ArgumentError) { Prism.find("not a callable") }
      assert_raise(ArgumentError) { Prism.find(42) }
      assert_raise(ArgumentError) { Prism.find(nil) }
    end

    def test_eval_returns_nil
      # eval'd code has no file on disk
      m = eval("proc { 1 }")
      assert_nil Prism.find(m)
    end

    def test_multiple_methods_on_same_line
      assert_def_node Prism.find(Fixtures::MultipleOnLine.method(:first)), :first
      assert_def_node Prism.find(Fixtures::MultipleOnLine.method(:second)), :second
    end

    # === Fallback (line-based) tests via rubyvm: false ===

    def test_fallback_simple_method
      assert_def_node Prism.find(Fixtures::Methods.instance_method(:simple_method), rubyvm: false), :simple_method
    end

    def test_fallback_singleton_method
      assert_def_node Prism.find(Fixtures::Methods.method(:singleton_method_fixture), rubyvm: false), :singleton_method_fixture
    end

    def test_fallback_lambda
      node = Prism.find(Fixtures::Procs::SIMPLE_LAMBDA, rubyvm: false)
      assert_instance_of LambdaNode, node
    end

    def test_fallback_proc
      node = Prism.find(Fixtures::Procs::SIMPLE_PROC, rubyvm: false)
      assert_instance_of CallNode, node
      assert node.block.is_a?(BlockNode)
    end

    def test_fallback_define_method
      node = Prism.find(Fixtures::DefineMethod.instance_method(:dynamic), rubyvm: false)
      assert_instance_of CallNode, node
      assert node.block.is_a?(BlockNode)
    end

    def test_fallback_for_loop
      node = Prism.find(Fixtures::ForLoop::FOR_PROC, rubyvm: false)
      assert_instance_of ForNode, node
    end

    def test_fallback_backtrace_location
      location = zero_division_location
      assert_not_nil location
      node = Prism.find(location, rubyvm: false)
      assert_not_nil node
      assert_equal location.lineno, node.location.start_line
    end

    # === Node identity with node_id (CRuby only) ===

    if defined?(RubyVM::InstructionSequence)
      def test_node_id_matches_iseq
        m = Fixtures::Methods.instance_method(:simple_method)
        node = Prism.find(m)
        assert_equal node_id_of(m), node.node_id
      end

      def test_node_id_for_lambda
        node = Prism.find(Fixtures::Procs::SIMPLE_LAMBDA)
        assert_equal node_id_of(Fixtures::Procs::SIMPLE_LAMBDA), node.node_id
      end

      def test_node_id_for_proc
        node = Prism.find(Fixtures::Procs::SIMPLE_PROC)
        assert_equal node_id_of(Fixtures::Procs::SIMPLE_PROC), node.node_id
      end

      def test_node_id_for_define_method
        m = Fixtures::DefineMethod.instance_method(:dynamic)
        node = Prism.find(m)
        assert_equal node_id_of(m), node.node_id
      end

      def test_node_id_for_backtrace_location
        location = zero_division_location
        assert_not_nil location
        expected_node_id = RubyVM::AbstractSyntaxTree.node_id_for_backtrace_location(location)

        node = Prism.find(location)
        assert_equal expected_node_id, node.node_id
      end
    end

    private

    def assert_def_node(node, expected_name)
      assert_instance_of DefNode, node
      assert_equal expected_name, node.name
    end

    def fixture_backtrace_location(exception)
      exception.backtrace_locations.find { |loc| loc.path == FIXTURES_PATH }
    end

    def zero_division_location
      Fixtures::Errors.divide(1, 0)
    rescue ZeroDivisionError => e
      fixture_backtrace_location(e)
    end

    def node_id_of(callable)
      RubyVM::InstructionSequence.of(callable).to_a[4][:node_id]
    end
  end
end
