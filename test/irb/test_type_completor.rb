# frozen_string_literal: true

# Run test only when Ruby >= 3.0 and repl_type_completor is available
return unless RUBY_VERSION >= '3.0.0'
return if RUBY_ENGINE == 'truffleruby' # needs endless method definition
begin
  require 'repl_type_completor'
rescue LoadError
  return
end

require 'irb'
require 'tempfile'
require_relative './helper'

module TestIRB
  class TypeCompletorTest < TestCase
    DummyContext = Struct.new(:irb_path)

    def setup
      ReplTypeCompletor.load_rbs unless ReplTypeCompletor.rbs_loaded?
      context = DummyContext.new('(irb)')
      @completor = IRB::TypeCompletor.new(context)
    end

    def empty_binding
      binding
    end

    def assert_completion(preposing, target, binding: empty_binding, include: nil, exclude: nil)
      raise ArgumentError if include.nil? && exclude.nil?
      candidates = @completor.completion_candidates(preposing, target, '', bind: binding)
      assert ([*include] - candidates).empty?, "Expected #{candidates} to include #{include}" if include
      assert (candidates & [*exclude]).empty?, "Expected #{candidates} not to include #{exclude}" if exclude
    end

    def assert_doc_namespace(preposing, target, namespace, binding: empty_binding)
      @completor.completion_candidates(preposing, target, '', bind: binding)
      assert_equal namespace, @completor.doc_namespace(preposing, target, '', bind: binding)
    end

    def test_type_completion
      bind = eval('num = 1; binding')
      assert_completion('num.times.map(&:', 'ab', binding: bind, include: 'abs')
      assert_doc_namespace('num.chr.', 'upcase', 'String#upcase', binding: bind)
    end

    def test_inspect
      assert_match(/\AReplTypeCompletor.*\z/, @completor.inspect)
    end

    def test_empty_completion
      candidates = @completor.completion_candidates('(', ')', '', bind: binding)
      assert_equal [], candidates
      assert_doc_namespace('(', ')', nil)
    end

    def test_command_completion
      binding.eval("some_var = 1")
      # completion for help command's argument should only include command names
      assert_include(@completor.completion_candidates('help ', 's', '', bind: binding), 'show_source')
      assert_not_include(@completor.completion_candidates('help ', 's', '', bind: binding), 'some_var')

      assert_include(@completor.completion_candidates('', 'show_s', '', bind: binding), 'show_source')
      assert_not_include(@completor.completion_candidates(';', 'show_s', '', bind: binding), 'show_source')
    end
  end

  class TypeCompletorIntegrationTest < IntegrationTestCase
    def test_type_completor
      write_rc <<~RUBY
        IRB.conf[:COMPLETOR] = :type
      RUBY

      write_ruby <<~'RUBY'
        binding.irb
      RUBY

      output = run_ruby_file do
        type "irb_info"
        type "sleep 0.01 until ReplTypeCompletor.rbs_loaded?"
        type "completor = IRB.CurrentContext.io.instance_variable_get(:@completor);"
        type "n = 10"
        type "puts completor.completion_candidates 'a = n.abs;', 'a.b', '', bind: binding"
        type "puts completor.doc_namespace 'a = n.chr;', 'a.encoding', '', bind: binding"
        type "exit!"
      end
      assert_match(/Completion: Autocomplete, ReplTypeCompletor/, output)
      assert_match(/a\.bit_length/, output)
      assert_match(/String#encoding/, output)
    end
  end
end
