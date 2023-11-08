# frozen_string_literal: true

# Run test only when Ruby >= 3.0 and %w[prism rbs] are available
return unless RUBY_VERSION >= '3.0.0'
return if RUBY_ENGINE == 'truffleruby' # needs endless method definition
begin
  require 'prism'
  require 'rbs'
rescue LoadError
  return
end

require 'irb/type_completion/completor'
require_relative '../helper'

module TestIRB
  class TypeCompletorTest < TestCase
    def setup
      IRB::TypeCompletion::Types.load_rbs_builder unless IRB::TypeCompletion::Types.rbs_builder
      @completor = IRB::TypeCompletion::Completor.new
    end

    def empty_binding
      binding
    end

    TARGET_REGEXP = /(@@|@|\$)?[a-zA-Z_]*[!?=]?$/

    def assert_completion(code, binding: empty_binding, include: nil, exclude: nil)
      raise ArgumentError if include.nil? && exclude.nil?
      target = code[TARGET_REGEXP]
      candidates = @completor.completion_candidates(code.delete_suffix(target), target, '', bind: binding)
      assert ([*include] - candidates).empty?, "Expected #{candidates} to include #{include}" if include
      assert (candidates & [*exclude]).empty?, "Expected #{candidates} not to include #{exclude}" if exclude
    end

    def assert_doc_namespace(code, namespace, binding: empty_binding)
      target = code[TARGET_REGEXP]
      preposing = code.delete_suffix(target)
      @completor.completion_candidates(preposing, target, '', bind: binding)
      assert_equal namespace, @completor.doc_namespace(preposing, target, '', bind: binding)
    end

    def test_require
      assert_completion("require '", include: 'set')
      assert_completion("require 's", include: 'set')
      Dir.chdir(__dir__ + "/../../..") do
        assert_completion("require_relative 'l", include: 'lib/irb')
      end
      # Incomplete double quote string is InterpolatedStringNode
      assert_completion('require "', include: 'set')
      assert_completion('require "s', include: 'set')
    end

    def test_method_block_sym
      assert_completion('[1].map(&:', include: 'abs')
      assert_completion('[:a].map(&:', exclude: 'abs')
      assert_completion('[1].map(&:a', include: 'abs')
      assert_doc_namespace('[1].map(&:abs', 'Integer#abs')
    end

    def test_symbol
      sym = :test_completion_symbol
      assert_completion(":test_com", include: sym.to_s)
    end

    def test_call
      assert_completion('1.', include: 'abs')
      assert_completion('1.a', include: 'abs')
      assert_completion('ran', include: 'rand')
      assert_doc_namespace('1.abs', 'Integer#abs')
      assert_doc_namespace('Integer.sqrt', 'Integer.sqrt')
      assert_doc_namespace('rand', 'TestIRB::TypeCompletorTest#rand')
      assert_doc_namespace('Object::rand', 'Object.rand')
    end

    def test_lvar
      bind = eval('lvar = 1; binding')
      assert_completion('lva', binding: bind, include: 'lvar')
      assert_completion('lvar.', binding: bind, include: 'abs')
      assert_completion('lvar.a', binding: bind, include: 'abs')
      assert_completion('lvar = ""; lvar.', binding: bind, include: 'ascii_only?')
      assert_completion('lvar = ""; lvar.', include: 'ascii_only?')
      assert_doc_namespace('lvar', 'Integer', binding: bind)
      assert_doc_namespace('lvar.abs', 'Integer#abs', binding: bind)
      assert_doc_namespace('lvar = ""; lvar.ascii_only?', 'String#ascii_only?', binding: bind)
    end

    def test_const
      assert_completion('Ar', include: 'Array')
      assert_completion('::Ar', include: 'Array')
      assert_completion('IRB::V', include: 'VERSION')
      assert_completion('FooBar=1; F', include: 'FooBar')
      assert_completion('::FooBar=1; ::F', include: 'FooBar')
      assert_doc_namespace('Array', 'Array')
      assert_doc_namespace('Array = 1; Array', 'Integer')
      assert_doc_namespace('Object::Array', 'Array')
      assert_completion('::', include: 'Array')
      assert_completion('class ::', include: 'Array')
      assert_completion('module IRB; class T', include: ['TypeCompletion', 'TracePoint'])
    end

    def test_gvar
      assert_completion('$', include: '$stdout')
      assert_completion('$s', include: '$stdout')
      assert_completion('$', exclude: '$foobar')
      assert_completion('$foobar=1; $', include: '$foobar')
      assert_doc_namespace('$foobar=1; $foobar', 'Integer')
      assert_doc_namespace('$stdout', 'IO')
      assert_doc_namespace('$stdout=1; $stdout', 'Integer')
    end

    def test_ivar
      bind = Object.new.instance_eval { @foo = 1; binding }
      assert_completion('@', binding: bind, include: '@foo')
      assert_completion('@f', binding: bind, include: '@foo')
      assert_completion('@bar = 1; @', include: '@bar')
      assert_completion('@bar = 1; @b', include: '@bar')
      assert_doc_namespace('@bar = 1; @bar', 'Integer')
      assert_doc_namespace('@foo', 'Integer', binding: bind)
      assert_doc_namespace('@foo = 1.0; @foo', 'Float', binding: bind)
    end

    def test_cvar
      bind = eval('m=Module.new; module m::M; @@foo = 1; binding; end')
      assert_equal(1, bind.eval('@@foo'))
      assert_completion('@', binding: bind, include: '@@foo')
      assert_completion('@@', binding: bind, include: '@@foo')
      assert_completion('@@f', binding: bind, include: '@@foo')
      assert_doc_namespace('@@foo', 'Integer', binding: bind)
      assert_doc_namespace('@@foo = 1.0; @@foo', 'Float', binding: bind)
      assert_completion('@@bar = 1; @', include: '@@bar')
      assert_completion('@@bar = 1; @@', include: '@@bar')
      assert_completion('@@bar = 1; @@b', include: '@@bar')
      assert_doc_namespace('@@bar = 1; @@bar', 'Integer')
    end

    def test_basic_object
      bo = BasicObject.new
      def bo.foo; end
      bo.instance_eval { @bar = 1 }
      bind = binding
      bo_self_bind = bo.instance_eval { Kernel.binding }
      assert_completion('bo.', binding: bind, include: 'foo')
      assert_completion('def bo.baz; self.', binding: bind, include: 'foo')
      assert_completion('[bo].first.', binding: bind, include: 'foo')
      assert_doc_namespace('bo', 'BasicObject', binding: bind)
      assert_doc_namespace('bo.__id__', 'BasicObject#__id__', binding: bind)
      assert_doc_namespace('v = [bo]; v', 'Array', binding: bind)
      assert_doc_namespace('v = [bo].first; v', 'BasicObject', binding: bind)
      bo_self_bind = bo.instance_eval { Kernel.binding }
      assert_completion('self.', binding: bo_self_bind, include: 'foo')
      assert_completion('@', binding: bo_self_bind, include: '@bar')
      assert_completion('@bar.', binding: bo_self_bind, include: 'abs')
      assert_doc_namespace('self.__id__', 'BasicObject#__id__', binding: bo_self_bind)
      assert_doc_namespace('@bar', 'Integer', binding: bo_self_bind)
      if RUBY_VERSION >= '3.2.0' # Needs Class#attached_object to get instance variables from singleton class
        assert_completion('def bo.baz; @bar.', binding: bind, include: 'abs')
        assert_completion('def bo.baz; @', binding: bind, include: '@bar')
      end
    end

    def test_inspect
      rbs_builder = IRB::TypeCompletion::Types.rbs_builder
      assert_match(/TypeCompletion::Completor\(Prism: \d.+, RBS: \d.+\)/, @completor.inspect)
      IRB::TypeCompletion::Types.instance_variable_set(:@rbs_builder, nil)
      assert_match(/TypeCompletion::Completor\(Prism: \d.+, RBS: loading\)/, @completor.inspect)
      IRB::TypeCompletion::Types.instance_variable_set(:@rbs_load_error, StandardError.new('[err]'))
      assert_match(/TypeCompletion::Completor\(Prism: \d.+, RBS: .+\[err\].+\)/, @completor.inspect)
    ensure
      IRB::TypeCompletion::Types.instance_variable_set(:@rbs_builder, rbs_builder)
      IRB::TypeCompletion::Types.instance_variable_set(:@rbs_load_error, nil)
    end

    def test_none
      candidates = @completor.completion_candidates('(', ')', '', bind: binding)
      assert_equal [], candidates
      assert_doc_namespace('()', nil)
    end
  end
end
