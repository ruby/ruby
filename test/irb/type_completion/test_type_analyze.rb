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


require 'irb/completion'
require 'irb/type_completion/completor'
require_relative '../helper'

module TestIRB
  class TypeCompletionAnalyzeTest < TestCase
    def setup
      IRB::TypeCompletion::Types.load_rbs_builder unless IRB::TypeCompletion::Types.rbs_builder
    end

    def empty_binding
      binding
    end

    def analyze(code, binding: nil)
      completor = IRB::TypeCompletion::Completor.new
      def completor.handle_error(e)
        raise e
      end
      completor.analyze(code, binding || empty_binding)
    end

    def assert_analyze_type(code, type, token = nil, binding: empty_binding)
      result_type, result_token = analyze(code, binding: binding)
      assert_equal type, result_type
      assert_equal token, result_token if token
    end

    def assert_call(code, include: nil, exclude: nil, binding: nil)
      raise ArgumentError if include.nil? && exclude.nil?

      result = analyze(code.strip, binding: binding)
      type = result[1] if result[0] == :call
      klasses = type.types.flat_map do
        _1.klass.singleton_class? ? [_1.klass.superclass, _1.klass] : _1.klass
      end
      assert ([*include] - klasses).empty?, "Expected #{klasses} to include #{include}" if include
      assert (klasses & [*exclude]).empty?, "Expected #{klasses} not to include #{exclude}" if exclude
    end

    def test_lvar_ivar_gvar_cvar
      assert_analyze_type('puts(x', :lvar_or_method, 'x')
      assert_analyze_type('puts($', :gvar, '$')
      assert_analyze_type('puts($x', :gvar, '$x')
      assert_analyze_type('puts(@', :ivar, '@')
      assert_analyze_type('puts(@x', :ivar, '@x')
      assert_analyze_type('puts(@@', :cvar, '@@')
      assert_analyze_type('puts(@@x', :cvar, '@@x')
    end

    def test_rescue
      assert_call '(1 rescue 1.0).', include: [Integer, Float]
      assert_call 'a=""; (a=1) rescue (a=1.0); a.', include: [Integer, Float], exclude: String
      assert_call 'begin; 1; rescue; 1.0; end.', include: [Integer, Float]
      assert_call 'begin; 1; rescue A; 1.0; rescue B; 1i; end.', include: [Integer, Float, Complex]
      assert_call 'begin; 1i; rescue; 1.0; else; 1; end.', include: [Integer, Float], exclude: Complex
      assert_call 'begin; 1; rescue; 1.0; ensure; 1i; end.', include: [Integer, Float], exclude: Complex
      assert_call 'begin; 1i; rescue; 1.0; else; 1; ensure; 1i; end.', include: [Integer, Float], exclude: Complex
      assert_call 'a=""; begin; a=1; rescue; a=1.0; end; a.', include: [Integer, Float], exclude: [String]
      assert_call 'a=""; begin; a=1; rescue; a=1.0; else; a=1r; end; a.', include: [Float, Rational], exclude: [String, Integer]
      assert_call 'a=""; begin; a=1; rescue; a=1.0; else; a=1r; ensure; a = 1i; end; a.', include: Complex, exclude: [Float, Rational, String, Integer]
    end

    def test_rescue_assign
      assert_equal [:lvar_or_method, 'a'], analyze('begin; rescue => a')[0, 2]
      assert_equal [:gvar, '$a'], analyze('begin; rescue => $a')[0, 2]
      assert_equal [:ivar, '@a'], analyze('begin; rescue => @a')[0, 2]
      assert_equal [:cvar, '@@a'], analyze('begin; rescue => @@a')[0, 2]
      assert_equal [:const, 'A'], analyze('begin; rescue => A').values_at(0, 2)
      assert_equal [:call, 'b'], analyze('begin; rescue => a.b').values_at(0, 2)
    end

    def test_ref
      bind = eval <<~RUBY
        class (Module.new)::A
          @ivar = :a
          @@cvar = 'a'
          binding
        end
      RUBY
      assert_call('STDIN.', include: STDIN.singleton_class)
      assert_call('$stdin.', include: $stdin.singleton_class)
      assert_call('@ivar.', include: Symbol, binding: bind)
      assert_call('@@cvar.', include: String, binding: bind)
      lbind = eval('lvar = 1; binding')
      assert_call('lvar.', include: Integer, binding: lbind)
    end

    def test_self_ivar_ref
      obj = Object.new
      obj.instance_variable_set(:@hoge, 1)
      assert_call('obj.instance_eval { @hoge.', include: Integer, binding: obj.instance_eval { binding })
      if Class.method_defined? :attached_object
        bind = binding
        assert_call('obj.instance_eval { @hoge.', include: Integer, binding: bind)
        assert_call('@hoge = 1.0; obj.instance_eval { @hoge.', include: Integer, exclude: Float, binding: bind)
        assert_call('@hoge = 1.0; obj.instance_eval { @hoge = "" }; @hoge.', include: Float, exclude: [Integer, String], binding: bind)
        assert_call('@fuga = 1.0; obj.instance_eval { @fuga.', exclude: Float, binding: bind)
        assert_call('@fuga = 1.0; obj.instance_eval { @fuga = "" }; @fuga.', include: Float, exclude: [Integer, String], binding: bind)
      end
    end

    class CVarModule
      @@test_cvar = 1
    end
    def test_module_cvar_ref
      bind = binding
      assert_call('@@foo=1; class A; @@foo.', exclude: Integer, binding: bind)
      assert_call('@@foo=1; class A; @@foo=1.0; @@foo.', include: Float, exclude: Integer, binding: bind)
      assert_call('@@foo=1; class A; @@foo=1.0; end; @@foo.', include: Integer, exclude: Float, binding: bind)
      assert_call('module CVarModule; @@test_cvar.', include: Integer, binding: bind)
      assert_call('class Array; @@foo = 1; end; class Array; @@foo.', include: Integer, binding: bind)
      assert_call('class Array; class B; @@foo = 1; end; class B; @@foo.', include: Integer, binding: bind)
      assert_call('class Array; class B; @@foo = 1; end; @@foo.', exclude: Integer, binding: bind)
    end

    def test_lvar_singleton_method
      a = 1
      b = +''
      c = Object.new
      d = [a, b, c]
      binding = Kernel.binding
      assert_call('a.', include: Integer, exclude: String, binding: binding)
      assert_call('b.', include: b.singleton_class, exclude: [Integer, Object], binding: binding)
      assert_call('c.', include: c.singleton_class, exclude: [Integer, String], binding: binding)
      assert_call('d.', include: d.class, exclude: [Integer, String, Object], binding: binding)
      assert_call('d.sample.', include: [Integer, String, Object], exclude: [b.singleton_class, c.singleton_class], binding: binding)
    end

    def test_local_variable_assign
      assert_call('(a = 1).', include: Integer)
      assert_call('a = 1; a = ""; a.', include: String, exclude: Integer)
      assert_call('1 => a; a.', include: Integer)
    end

    def test_block_symbol
      assert_call('[1].map(&:', include: Integer)
      assert_call('1.to_s.tap(&:', include: String)
    end

    def test_union_splat
      assert_call('a, = [[:a], 1, nil].sample; a.', include: [Symbol, Integer, NilClass], exclude: Object)
      assert_call('[[:a], 1, nil].each do _2; _1.', include: [Symbol, Integer, NilClass], exclude: Object)
      assert_call('a = [[:a], 1, nil, ("a".."b")].sample; [*a].sample.', include: [Symbol, Integer, NilClass, String], exclude: Object)
    end

    def test_range
      assert_call('(1..2).first.', include: Integer)
      assert_call('("a".."b").first.', include: String)
      assert_call('(..1.to_f).first.', include: Float)
      assert_call('(1.to_s..).first.', include: String)
      assert_call('(1..2.0).first.', include: [Float, Integer])
    end

    def test_conditional_assign
      assert_call('a = 1; a = "" if cond; a.', include: [String, Integer], exclude: NilClass)
      assert_call('a = 1 if cond; a.', include: [Integer, NilClass])
      assert_call(<<~RUBY, include: [String, Symbol], exclude: [Integer, NilClass])
        a = 1
        cond ? a = '' : a = :a
        a.
      RUBY
    end

    def test_block
      assert_call('nil.then{1}.', include: Integer, exclude: NilClass)
      assert_call('nil.then(&:to_s).', include: String, exclude: NilClass)
    end

    def test_block_break
      assert_call('1.tap{}.', include: [Integer], exclude: NilClass)
      assert_call('1.tap{break :a}.', include: [Symbol, Integer], exclude: NilClass)
      assert_call('1.tap{break :a, :b}[0].', include: Symbol)
      assert_call('1.tap{break :a; break "a"}.', include: [Symbol, Integer], exclude: [NilClass, String])
      assert_call('1.tap{break :a if b}.', include: [Symbol, Integer], exclude: NilClass)
      assert_call('1.tap{break :a; break "a" if b}.', include: [Symbol, Integer], exclude: [NilClass, String])
      assert_call('1.tap{if cond; break :a; else; break "a"; end}.', include: [Symbol, Integer, String], exclude: NilClass)
    end

    def test_instance_eval
      assert_call('1.instance_eval{:a.then{self.', include: Integer, exclude: Symbol)
      assert_call('1.then{:a.instance_eval{self.', include: Symbol, exclude: Integer)
    end

    def test_block_next
      assert_call('nil.then{1}.', include: Integer, exclude: [NilClass, Object])
      assert_call('nil.then{next 1}.', include: Integer, exclude: [NilClass, Object])
      assert_call('nil.then{next :a, :b}[0].', include: Symbol)
      assert_call('nil.then{next 1; 1.0}.', include: Integer, exclude: [Float, NilClass, Object])
      assert_call('nil.then{next 1; next 1.0}.', include: Integer, exclude: [Float, NilClass, Object])
      assert_call('nil.then{1 if cond}.', include: [Integer, NilClass], exclude: Object)
      assert_call('nil.then{if cond; 1; else; 1.0; end}.', include: [Integer, Float], exclude: [NilClass, Object])
      assert_call('nil.then{next 1 if cond; 1.0}.', include: [Integer, Float], exclude: [NilClass, Object])
      assert_call('nil.then{if cond; next 1; else; next 1.0; end; "a"}.', include: [Integer, Float], exclude: [String, NilClass, Object])
      assert_call('nil.then{if cond; next 1; else; next 1.0; end; next "a"}.', include: [Integer, Float], exclude: [String, NilClass, Object])
    end

    def test_vars_with_branch_termination
      assert_call('a=1; tap{break; a=//}; a.', include: Integer, exclude: Regexp)
      assert_call('a=1; tap{a=1.0; break; a=//}; a.', include: [Integer, Float], exclude: Regexp)
      assert_call('a=1; tap{next; a=//}; a.', include: Integer, exclude: Regexp)
      assert_call('a=1; tap{a=1.0; next; a=//}; a.', include: [Integer, Float], exclude: Regexp)
      assert_call('a=1; while cond; break; a=//; end; a.', include: Integer, exclude: Regexp)
      assert_call('a=1; while cond; a=1.0; break; a=//; end; a.', include: [Integer, Float], exclude: Regexp)
      assert_call('a=1; ->{ break; a=// }; a.', include: Integer, exclude: Regexp)
      assert_call('a=1; ->{ a=1.0; break; a=// }; a.', include: [Integer, Float], exclude: Regexp)

      assert_call('a=1; tap{ break; a=// if cond }; a.', include: Integer, exclude: Regexp)
      assert_call('a=1; tap{ next; a=// if cond }; a.', include: Integer, exclude: Regexp)
      assert_call('a=1; while cond; break; a=// if cond; end; a.', include: Integer, exclude: Regexp)
      assert_call('a=1; ->{ break; a=// if cond }; a.', include: Integer, exclude: Regexp)

      assert_call('a=1; tap{if cond; a=:a; break; a=""; end; a.', include: Integer, exclude: [Symbol, String])
      assert_call('a=1; tap{if cond; a=:a; break; a=""; end; a=//}; a.', include: [Integer, Symbol, Regexp], exclude: String)
      assert_call('a=1; tap{if cond; a=:a; break; a=""; else; break; end; a=//}; a.', include: [Integer, Symbol], exclude: [String, Regexp])
      assert_call('a=1; tap{if cond; a=:a; next; a=""; end; a.', include: Integer, exclude: [Symbol, String])
      assert_call('a=1; tap{if cond; a=:a; next; a=""; end; a=//}; a.', include: [Integer, Symbol, Regexp], exclude: String)
      assert_call('a=1; tap{if cond; a=:a; next; a=""; else; next; end; a=//}; a.', include: [Integer, Symbol], exclude: [String, Regexp])
      assert_call('def f(a=1); if cond; a=:a; return; a=""; end; a.', include: Integer, exclude: [Symbol, String])
      assert_call('a=1; while cond; if cond; a=:a; break; a=""; end; a.', include: Integer, exclude: [Symbol, String])
      assert_call('a=1; while cond; if cond; a=:a; break; a=""; end; a=//; end; a.', include: [Integer, Symbol, Regexp], exclude: String)
      assert_call('a=1; while cond; if cond; a=:a; break; a=""; else; break; end; a=//; end; a.', include: [Integer, Symbol], exclude: [String, Regexp])
      assert_call('a=1; ->{ if cond; a=:a; break; a=""; end; a.', include: Integer, exclude: [Symbol, String])
      assert_call('a=1; ->{ if cond; a=:a; break; a=""; end; a=// }; a.', include: [Integer, Symbol, Regexp], exclude: String)
      assert_call('a=1; ->{ if cond; a=:a; break; a=""; else; break; end; a=// }; a.', include: [Integer, Symbol], exclude: [String, Regexp])

      # continue evaluation on terminated branch
      assert_call('a=1; tap{ a=1.0; break; a=// if cond; a.', include: [Regexp, Float], exclude: Integer)
      assert_call('a=1; tap{ a=1.0; next; a=// if cond; a.', include: [Regexp, Float], exclude: Integer)
      assert_call('a=1; ->{ a=1.0; break; a=// if cond; a.', include: [Regexp, Float], exclude: Integer)
      assert_call('a=1; while cond; a=1.0; break; a=// if cond; a.', include: [Regexp, Float], exclude: Integer)
    end

    def test_to_str_to_int
      sobj = Struct.new(:to_str).new('a')
      iobj = Struct.new(:to_int).new(1)
      binding = Kernel.binding
      assert_equal String, ([] * sobj).class
      assert_equal Array, ([] * iobj).class
      assert_call('([]*sobj).', include: String, exclude: Array, binding: binding)
      assert_call('([]*iobj).', include: Array, exclude: String, binding: binding)
    end

    def test_method_select
      assert_call('([]*4).', include: Array, exclude: String)
      assert_call('([]*"").', include: String, exclude: Array)
      assert_call('([]*unknown).', include: [String, Array])
      assert_call('p(1).', include: Integer)
      assert_call('p(1, 2).', include: Array, exclude: Integer)
      assert_call('2.times.', include: Enumerator, exclude: Integer)
      assert_call('2.times{}.', include: Integer, exclude: Enumerator)
    end

    def test_interface_match_var
      assert_call('([1]+[:a]+["a"]).sample.', include: [Integer, String, Symbol])
    end

    def test_lvar_scope
      code = <<~RUBY
        tap { a = :never }
        a = 1 if x?
        tap {|a| a = :never }
        tap { a = 'maybe' }
        a = {} if x?
        a.
      RUBY
      assert_call(code, include: [Hash, Integer, String], exclude: [Symbol])
    end

    def test_lvar_scope_complex
      assert_call('if cond; a = 1; else; tap { a = :a }; end; a.', include: [NilClass, Integer, Symbol], exclude: [Object])
      assert_call('def f; if cond; a = 1; return; end; tap { a = :a }; a.', include: [NilClass, Symbol], exclude: [Integer, Object])
      assert_call('def f; if cond; return; a = 1; end; tap { a = :a }; a.', include: [NilClass, Symbol], exclude: [Integer, Object])
      assert_call('def f; if cond; return; if cond; return; a = 1; end; end; tap { a = :a }; a.', include: [NilClass, Symbol], exclude: [Integer, Object])
      assert_call('def f; if cond; return; if cond; return; a = 1; end; end; tap { a = :a }; a.', include: [NilClass, Symbol], exclude: [Integer, Object])
    end

    def test_gvar_no_scope
      code = <<~RUBY
        tap { $a = :maybe }
        $a = 'maybe' if x?
        $a.
      RUBY
      assert_call(code, include: [Symbol, String])
    end

    def test_ivar_no_scope
      code = <<~RUBY
        tap { @a = :maybe }
        @a = 'maybe' if x?
        @a.
      RUBY
      assert_call(code, include: [Symbol, String])
    end

    def test_massign
      assert_call('(a,=1).', include: Integer)
      assert_call('(a,=[*1])[0].', include: Integer)
      assert_call('(a,=[1,2])[0].', include: Integer)
      assert_call('a,=[1,2]; a.', include: Integer, exclude: Array)
      assert_call('a,b=[1,2]; a.', include: Integer, exclude: Array)
      assert_call('a,b=[1,2]; b.', include: Integer, exclude: Array)
      assert_call('a,*,b=[1,2]; a.', include: Integer, exclude: Array)
      assert_call('a,*,b=[1,2]; b.', include: Integer, exclude: Array)
      assert_call('a,*b=[1,2]; a.', include: Integer, exclude: Array)
      assert_call('a,*b=[1,2]; b.', include: Array, exclude: Integer)
      assert_call('a,*b=[1,2]; b.sample.', include: Integer)
      assert_call('a,*,(*)=[1,2]; a.', include: Integer)
      assert_call('*a=[1,2]; a.', include: Array, exclude: Integer)
      assert_call('*a=[1,2]; a.sample.', include: Integer)
      assert_call('a,*b,c=[1,2,3]; b.', include: Array, exclude: Integer)
      assert_call('a,*b,c=[1,2,3]; b.sample.', include: Integer)
      assert_call('a,b=(cond)?[1,2]:[:a,:b]; a.', include: [Integer, Symbol])
      assert_call('a,b=(cond)?[1,2]:[:a,:b]; b.', include: [Integer, Symbol])
      assert_call('a,b=(cond)?[1,2]:"s"; a.', include: [Integer, String])
      assert_call('a,b=(cond)?[1,2]:"s"; b.', include: Integer, exclude: String)
      assert_call('a,*b=(cond)?[1,2]:"s"; a.', include: [Integer, String])
      assert_call('a,*b=(cond)?[1,2]:"s"; b.', include: Array, exclude: [Integer, String])
      assert_call('a,*b=(cond)?[1,2]:"s"; b.sample.', include: Integer, exclude: String)
      assert_call('*a=(cond)?[1,2]:"s"; a.', include: Array, exclude: [Integer, String])
      assert_call('*a=(cond)?[1,2]:"s"; a.sample.', include: [Integer, String])
      assert_call('a,(b,),c=[1,[:a],4]; b.', include: Symbol)
      assert_call('a,(b,(c,))=1; a.', include: Integer)
      assert_call('a,(b,(*c))=1; c.', include: Array)
      assert_call('(a=1).b, c = 1; a.', include: Integer)
      assert_call('a, ((b=1).c, d) = 1; b.', include: Integer)
      assert_call('a, b[c=1] = 1; c.', include: Integer)
      assert_call('a, b[*(c=1)] = 1; c.', include: Integer)
      # incomplete massign
      assert_analyze_type('a,b', :lvar_or_method, 'b')
      assert_call('(a=1).b, a.', include: Integer)
      assert_call('a=1; *a.', include: Integer)
    end

    def test_field_assign
      assert_call('(a.!=1).', exclude: Integer)
      assert_call('(a.b=1).', include: Integer, exclude: NilClass)
      assert_call('(a&.b=1).', include: Integer)
      assert_call('(nil&.b=1).', include: NilClass)
      assert_call('(a[]=1).', include: Integer)
      assert_call('(a[b]=1).', include: Integer)
      assert_call('(a.[]=1).', exclude: Integer)
    end

    def test_def
      assert_call('def f; end.', include: Symbol)
      assert_call('s=""; def s.f; self.', include: String)
      assert_call('def (a="").f; end; a.', include: String)
      assert_call('def f(a=1); a.', include: Integer)
      assert_call('def f(**nil); 1.', include: Integer)
      assert_call('def f((*),*); 1.', include: Integer)
      assert_call('def f(a,*b); b.', include: Array)
      assert_call('def f(a,x:1); x.', include: Integer)
      assert_call('def f(a,x:,**); 1.', include: Integer)
      assert_call('def f(a,x:,**y); y.', include: Hash)
      assert_call('def f((*a)); a.', include: Array)
      assert_call('def f(a,b=1,*c,d,x:0,y:,**z,&e); e.arity.', include: Integer)
      assert_call('def f(...); 1.', include: Integer)
      assert_call('def f(a,...); 1.', include: Integer)
      assert_call('def f(...); g(...); 1.', include: Integer)
      assert_call('def f(*,**,&); g(*,**,&); 1.', include: Integer)
      assert_call('def f(*,**,&); {**}.', include: Hash)
      assert_call('def f(*,**,&); [*,**].', include: Array)
      assert_call('class Array; def f; self.', include: Array)
    end

    def test_defined
      assert_call('defined?(a.b+c).', include: [String, NilClass])
      assert_call('defined?(a = 1); tap { a = 1.0 }; a.', include: [Integer, Float, NilClass])
    end

    def test_ternary_operator
      assert_call('condition ? 1.chr.', include: [String])
      assert_call('condition ? value : 1.chr.', include: [String])
      assert_call('condition ? cond ? cond ? value : cond ? value : 1.chr.', include: [String])
    end

    def test_block_parameter
      assert_call('method { |arg = 1.chr.', include: [String])
      assert_call('method do |arg = 1.chr.', include: [String])
      assert_call('method { |arg1 = 1.|(2|3), arg2 = 1.chr.', include: [String])
      assert_call('method do |arg1 = 1.|(2|3), arg2 = 1.chr.', include: [String])
    end

    def test_self
      integer_binding = 1.instance_eval { Kernel.binding }
      assert_call('self.', include: [Integer], binding: integer_binding)
      string = +''
      string_binding = string.instance_eval { Kernel.binding }
      assert_call('self.', include: [string.singleton_class], binding: string_binding)
      object = Object.new
      object.instance_eval { @int = 1; @string = string }
      object_binding = object.instance_eval { Kernel.binding }
      assert_call('self.', include: [object.singleton_class], binding: object_binding)
      assert_call('@int.', include: [Integer], binding: object_binding)
      assert_call('@string.', include: [String], binding: object_binding)
    end

    def test_optional_chain
      assert_call('[1,nil].sample.', include: [Integer, NilClass])
      assert_call('[1,nil].sample&.', include: [Integer], exclude: [NilClass])
      assert_call('[1,nil].sample.chr.', include: [String], exclude: [NilClass])
      assert_call('[1,nil].sample&.chr.', include: [String, NilClass])
      assert_call('[1,nil].sample.chr&.ord.', include: [Integer], exclude: [NilClass])
      assert_call('a = 1; b.c(a = :a); a.', include: [Symbol], exclude: [Integer])
      assert_call('a = 1; b&.c(a = :a); a.', include: [Integer, Symbol])
    end

    def test_class_module
      assert_call('class (1.', include: Integer)
      assert_call('class (a=1)::B; end; a.', include: Integer)
      assert_call('class Array; 1; end.', include: Integer)
      assert_call('class ::Array; 1; end.', include: Integer)
      assert_call('class Array::A; 1; end.', include: Integer)
      assert_call('class Array; self.new.', include: Array)
      assert_call('class ::Array; self.new.', include: Array)
      assert_call('class Array::A; self.', include: Class)
      assert_call('class (a=1)::A; end; a.', include: Integer)
      assert_call('module M; 1; end.', include: Integer)
      assert_call('module ::M; 1; end.', include: Integer)
      assert_call('module Array::M; 1; end.', include: Integer)
      assert_call('module M; self.', include: Module)
      assert_call('module Array::M; self.', include: Module)
      assert_call('module ::M; self.', include: Module)
      assert_call('module (a=1)::M; end; a.', include: Integer)
      assert_call('class << Array; 1; end.', include: Integer)
      assert_call('class << a; 1; end.', include: Integer)
      assert_call('a = ""; class << a; self.superclass.', include: Class)
    end

    def test_constant_path
      assert_call('class A; X=1; class B; X=""; X.', include: String, exclude: Integer)
      assert_call('class A; X=1; class B; X=""; end; X.', include: Integer, exclude: String)
      assert_call('class A; class B; X=1; end; end; class A; class B; X.', include: Integer)
      assert_call('module IRB; VERSION.', include: String)
      assert_call('module IRB; IRB::VERSION.', include: String)
      assert_call('module IRB; VERSION=1; VERSION.', include: Integer)
      assert_call('module IRB; VERSION=1; IRB::VERSION.', include: Integer)
      assert_call('module IRB; module A; VERSION.', include: String)
      assert_call('module IRB; module A; VERSION=1; VERSION.', include: Integer)
      assert_call('module IRB; module A; VERSION=1; IRB::VERSION.', include: String)
      assert_call('module IRB; module A; VERSION=1; end; VERSION.', include: String)
      assert_call('module IRB; IRB=1; IRB.', include: Integer)
      assert_call('module IRB; IRB=1; ::IRB::VERSION.', include: String)
      module_binding = eval 'module ::IRB; binding; end'
      assert_call('VERSION.', include: NilClass)
      assert_call('VERSION.', include: String, binding: module_binding)
      assert_call('IRB::VERSION.', include: String, binding: module_binding)
      assert_call('A = 1; module M; A += 0.5; A.', include: Float)
      assert_call('::A = 1; module M; A += 0.5; A.', include: Float)
      assert_call('::A = 1; module M; A += 0.5; ::A.', include: Integer)
      assert_call('IRB::A = 1; IRB::A += 0.5; IRB::A.', include: Float)
    end

    def test_literal
      assert_call('1.', include: Integer)
      assert_call('1.0.', include: Float)
      assert_call('1r.', include: Rational)
      assert_call('1i.', include: Complex)
      assert_call('true.', include: TrueClass)
      assert_call('false.', include: FalseClass)
      assert_call('nil.', include: NilClass)
      assert_call('().', include: NilClass)
      assert_call('//.', include: Regexp)
      assert_call('/#{a=1}/.', include: Regexp)
      assert_call('/#{a=1}/; a.', include: Integer)
      assert_call(':a.', include: Symbol)
      assert_call(':"#{a=1}".', include: Symbol)
      assert_call(':"#{a=1}"; a.', include: Integer)
      assert_call('"".', include: String)
      assert_call('"#$a".', include: String)
      assert_call('("a" "b").', include: String)
      assert_call('"#{a=1}".', include: String)
      assert_call('"#{a=1}"; a.', include: Integer)
      assert_call('``.', include: String)
      assert_call('`#{a=1}`.', include: String)
      assert_call('`#{a=1}`; a.', include: Integer)
    end

    def test_redo_retry_yield_super
      assert_call('a=nil; tap do a=1; redo; a=1i; end; a.', include: Integer, exclude: Complex)
      assert_call('a=nil; tap do a=1; retry; a=1i; end; a.', include: Integer, exclude: Complex)
      assert_call('a = 0; a = yield; a.', include: Object, exclude: Integer)
      assert_call('yield 1,(a=1); a.', include: Integer)
      assert_call('a = 0; a = super; a.', include: Object, exclude: Integer)
      assert_call('a = 0; a = super(1); a.', include: Object, exclude: Integer)
      assert_call('super 1,(a=1); a.', include: Integer)
    end

    def test_rarely_used_syntax
      # FlipFlop
      assert_call('if (a=1).even?..(a=1.0).even; a.', include: [Integer, Float])
      # MatchLastLine
      assert_call('if /regexp/; 1.', include: Integer)
      assert_call('if /reg#{a=1}exp/; a.', include: Integer)
      # BlockLocalVariable
      assert_call('tap do |i;a| a=1; a.', include: Integer)
      # BEGIN{} END{}
      assert_call('BEGIN{1.', include: Integer)
      assert_call('END{1.', include: Integer)
      # MatchWrite
      assert_call('a=1; /(?<a>)/=~b; a.', include: [String, NilClass], exclude: Integer)
      # OperatorWrite with block `a[&b]+=c`
      assert_call('a=[1]; (a[0,&:to_a]+=1.0).', include: Float)
      assert_call('a=[1]; (a[0,&b]+=1.0).', include: Float)
    end

    def test_hash
      assert_call('{}.', include: Hash)
      assert_call('{**a}.', include: Hash)
      assert_call('{ rand: }.values.sample.', include: Float)
      assert_call('rand=""; { rand: }.values.sample.', include: String, exclude: Float)
      assert_call('{ 1 => 1.0 }.keys.sample.', include: Integer, exclude: Float)
      assert_call('{ 1 => 1.0 }.values.sample.', include: Float, exclude: Integer)
      assert_call('a={1=>1.0}; {"a"=>1i,**a}.keys.sample.', include: [Integer, String])
      assert_call('a={1=>1.0}; {"a"=>1i,**a}.values.sample.', include: [Float, Complex])
    end

    def test_array
      assert_call('[1,2,3].sample.', include: Integer)
      assert_call('a = 1.0; [1,2,a].sample.', include: [Integer, Float])
      assert_call('a = [1.0]; [1,2,*a].sample.', include: [Integer, Float])
    end

    def test_numbered_parameter
      assert_call('loop{_1.', include: NilClass)
      assert_call('1.tap{_1.', include: Integer)
      assert_call('1.tap{_3.', include: NilClass, exclude: Integer)
      assert_call('[:a,1].tap{_1.', include: Array, exclude: [Integer, Symbol])
      assert_call('[:a,1].tap{_2.', include: [Symbol, Integer], exclude: Array)
      assert_call('[:a,1].tap{_2; _1.', include: [Symbol, Integer], exclude: Array)
      assert_call('[:a].each_with_index{_1.', include: Symbol, exclude: [Integer, Array])
      assert_call('[:a].each_with_index{_2; _1.', include: Symbol, exclude: [Integer, Array])
      assert_call('[:a].each_with_index{_2.', include: Integer, exclude: Symbol)
    end

    def test_if_unless
      assert_call('if cond; 1; end.', include: Integer)
      assert_call('unless true; 1; end.', include: Integer)
      assert_call('a=1; (a=1.0) if cond; a.', include: [Integer, Float])
      assert_call('a=1; (a=1.0) unless cond; a.', include: [Integer, Float])
      assert_call('a=1; 123 if (a=1.0).foo; a.', include: Float, exclude: Integer)
      assert_call('if cond; a=1; end; a.', include: [Integer, NilClass])
      assert_call('a=1; if cond; a=1.0; elsif cond; a=1r; else; a=1i; end; a.', include: [Float, Rational, Complex], exclude: Integer)
      assert_call('a=1; if cond; a=1.0; else; a.', include: Integer, exclude: Float)
      assert_call('a=1; if (a=1.0).foo; a.', include: Float, exclude: Integer)
      assert_call('a=1; if (a=1.0).foo; end; a.', include: Float, exclude: Integer)
      assert_call('a=1; if (a=1.0).foo; else; a.', include: Float, exclude: Integer)
      assert_call('a=1; if (a=1.0).foo; elsif a.', include: Float, exclude: Integer)
      assert_call('a=1; if (a=1.0).foo; elsif (a=1i); else; a.', include: Complex, exclude: [Integer, Float])
    end

    def test_while_until
      assert_call('while cond; 123; end.', include: NilClass)
      assert_call('until cond; 123; end.', include: NilClass)
      assert_call('a=1; a=1.0 while cond; a.', include: [Integer, Float])
      assert_call('a=1; a=1.0 until cond; a.', include: [Integer, Float])
      assert_call('a=1; 1 while (a=1.0).foo; a.', include: Float, exclude: Integer)
      assert_call('while cond; break 1; end.', include: Integer)
      assert_call('while cond; a=1; end; a.', include: Integer)
      assert_call('a=1; while cond; a=1.0; end; a.', include: [Integer, Float])
      assert_call('a=1; while (a=1.0).foo; end; a.', include: Float, exclude: Integer)
    end

    def test_for
      assert_call('for i in [1,2,3]; i.', include: Integer)
      assert_call('for i,j in [1,2,3]; i.', include: Integer)
      assert_call('for *,(*) in [1,2,3]; 1.', include: Integer)
      assert_call('for *i in [1,2,3]; i.sample.', include: Integer)
      assert_call('for (a=1).b in [1,2,3]; a.', include: Integer)
      assert_call('for Array::B in [1,2,3]; Array::B.', include: Integer)
      assert_call('for A in [1,2,3]; A.', include: Integer)
      assert_call('for $a in [1,2,3]; $a.', include: Integer)
      assert_call('for @a in [1,2,3]; @a.', include: Integer)
      assert_call('for i in [1,2,3]; end.', include: Array)
      assert_call('for i in [1,2,3]; break 1.0; end.', include: [Array, Float])
      assert_call('i = 1.0; for i in [1,2,3]; end; i.', include: [Integer, Float])
      assert_call('a = 1.0; for i in [1,2,3]; a = 1i; end; a.', include: [Float, Complex])
    end

    def test_special_var
      assert_call('__FILE__.', include: String)
      assert_call('__LINE__.', include: Integer)
      assert_call('__ENCODING__.', include: Encoding)
      assert_call('$1.', include: String)
      assert_call('$&.', include: String)
    end

    def test_and_or
      assert_call('(1&&1.0).', include: Float, exclude: Integer)
      assert_call('(nil&&1.0).', include: NilClass)
      assert_call('(nil||1).', include: Integer)
      assert_call('(1||1.0).', include: Float)
    end

    def test_opwrite
      assert_call('a=[]; a*=1; a.', include: Array)
      assert_call('a=[]; a*=""; a.', include: String)
      assert_call('a=[1,false].sample; a||=1.0; a.', include: [Integer, Float])
      assert_call('a=1; a&&=1.0; a.', include: Float, exclude: Integer)
      assert_call('(a=1).b*=1; a.', include: Integer)
      assert_call('(a=1).b||=1; a.', include: Integer)
      assert_call('(a=1).b&&=1; a.', include: Integer)
      assert_call('[][a=1]&&=1; a.', include: Integer)
      assert_call('[][a=1]||=1; a.', include: Integer)
      assert_call('[][a=1]+=1; a.', include: Integer)
      assert_call('([1][0]+=1.0).', include: Float)
      assert_call('([1.0][0]+=1).', include: Float)
      assert_call('A=nil; A||=1; A.', include: Integer)
      assert_call('A=1; A&&=1.0; A.', include: Float)
      assert_call('A=1; A+=1.0; A.', include: Float)
      assert_call('Array::A||=1; Array::A.', include: Integer)
      assert_call('Array::A=1; Array::A&&=1.0; Array::A.', include: Float)
    end

    def test_case_when
      assert_call('case x; when A; 1; when B; 1.0; end.', include: [Integer, Float, NilClass])
      assert_call('case x; when A; 1; when B; 1.0; else; 1r; end.', include: [Integer, Float, Rational], exclude: NilClass)
      assert_call('case; when (a=1); a.', include: Integer)
      assert_call('case x; when (a=1); a.', include: Integer)
      assert_call('a=1; case (a=1.0); when A; a.', include: Float, exclude: Integer)
      assert_call('a=1; case (a=1.0); when A; end; a.', include: Float, exclude: Integer)
      assert_call('a=1; case x; when A; a=1.0; else; a=1r; end; a.', include: [Float, Rational], exclude: Integer)
      assert_call('a=1; case x; when A; a=1.0; when B; a=1r; end; a.', include: [Float, Rational, Integer])
    end

    def test_case_in
      assert_call('case x; in A; 1; in B; 1.0; end.', include: [Integer, Float], exclude: NilClass)
      assert_call('case x; in A; 1; in B; 1.0; else; 1r; end.', include: [Integer, Float, Rational], exclude: NilClass)
      assert_call('a=""; case 1; in A; a=1; in B; a=1.0; end; a.', include: [Integer, Float], exclude: String)
      assert_call('a=""; case 1; in A; a=1; in B; a=1.0; else; a=1r; end; a.', include: [Integer, Float, Rational], exclude: String)
      assert_call('case 1; in x; x.', include: Integer)
      assert_call('case x; in A if (a=1); a.', include: Integer)
      assert_call('case x; in ^(a=1); a.', include: Integer)
      assert_call('case x; in [1, String => a, 2]; a.', include: String)
      assert_call('case x; in [*a, 1]; a.', include: Array)
      assert_call('case x; in [1, *a]; a.', include: Array)
      assert_call('case x; in [*a, 1, *b]; a.', include: Array)
      assert_call('case x; in [*a, 1, *b]; b.', include: Array)
      assert_call('case x; in {a: {b: **c}}; c.', include: Hash)
      assert_call('case x; in (String | { x: Integer, y: ^$a }) => a; a.', include: [String, Hash])
    end

    def test_pattern_match
      assert_call('1 in a; a.', include: Integer)
      assert_call('a=1; x in String=>a; a.', include: [Integer, String])
      assert_call('a=1; x=>String=>a; a.', include: String, exclude: Integer)
    end

    def test_bottom_type_termination
      assert_call('a=1; tap { raise; a=1.0; a.', include: Float)
      assert_call('a=1; tap { loop{}; a=1.0; a.', include: Float)
      assert_call('a=1; tap { raise; a=1.0 } a.', include: Integer, exclude: Float)
      assert_call('a=1; tap { loop{}; a=1.0 } a.', include: Integer, exclude: Float)
    end

    def test_call_parameter
      assert_call('f((x=1),*b,c:1,**d,&e); x.', include: Integer)
      assert_call('f(a,*(x=1),c:1,**d,&e); x.', include: Integer)
      assert_call('f(a,*b,(x=1):1,**d,&e); x.', include: Integer)
      assert_call('f(a,*b,c:(x=1),**d,&e); x.', include: Integer)
      assert_call('f(a,*b,c:1,**(x=1),&e); x.', include: Integer)
      assert_call('f(a,*b,c:1,**d,&(x=1)); x.', include: Integer)
      assert_call('f((x=1)=>1); x.', include: Integer)
    end

    def test_block_args
      assert_call('[1,2,3].tap{|a| a.', include: Array)
      assert_call('[1,2,3].tap{|a,b| a.', include: Integer)
      assert_call('[1,2,3].tap{|(a,b)| a.', include: Integer)
      assert_call('[1,2,3].tap{|a,*b| b.', include: Array)
      assert_call('[1,2,3].tap{|a=1.0| a.', include: [Array, Float])
      assert_call('[1,2,3].tap{|a,**b| b.', include: Hash)
      assert_call('1.tap{|(*),*,**| 1.', include: Integer)
    end

    def test_array_aref
      assert_call('[1][0..].', include: [Array, NilClass], exclude: Integer)
      assert_call('[1][0].', include: Integer, exclude: [Array, NilClass])
      assert_call('[1].[](0).', include: Integer, exclude: [Array, NilClass])
      assert_call('[1].[](0){}.', include: Integer, exclude: [Array, NilClass])
    end
  end
end
