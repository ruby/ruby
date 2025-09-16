# frozen_string_literal: true

# This file is organized to match itemization in https://github.com/ruby/prism/issues/1335
module Prism
  class TestCompilePrism < Test::Unit::TestCase
    def test_iseq_has_node_id
      code = "proc { <<END }\n hello\nEND"
      iseq = RubyVM::InstructionSequence.compile_prism(code)
      assert_operator iseq.to_a[4][:node_id], :>, -1
    end

    # Subclass is used for tests which need it
    class Subclass; end
    ############################################################################
    # Literals                                                                 #
    ############################################################################

    def test_FalseNode
      assert_prism_eval("false")
    end

    def test_FloatNode
      assert_prism_eval("1.2")
      assert_prism_eval("1.2e3")
      assert_prism_eval("+1.2e+3")
      assert_prism_eval("-1.2e-3")
    end

    def test_ImaginaryNode
      assert_prism_eval("1i")
      assert_prism_eval("+1.0i")
      assert_prism_eval("1ri")
    end

    def test_IntegerNode
      assert_prism_eval("1")
      assert_prism_eval("+1")
      assert_prism_eval("-1")
      assert_prism_eval("0x10")
      assert_prism_eval("0b10")
      assert_prism_eval("0o10")
      assert_prism_eval("010")
      assert_prism_eval("(0o00)")
    end

    def test_NilNode
      assert_prism_eval("nil")
    end

    def test_RationalNode
      assert_prism_eval("1.2r")
      assert_prism_eval("+1.2r")
    end

    def test_SelfNode
      assert_prism_eval("self")
    end

    def test_SourceEncodingNode
      assert_prism_eval("__ENCODING__")
    end

    def test_SourceFileNode
      assert_prism_eval("__FILE__")
    end

    def test_SourceLineNode
      assert_prism_eval("__LINE__", raw: true)
    end

    def test_TrueNode
      assert_prism_eval("true")
    end

    ############################################################################
    # Reads                                                                    #
    ############################################################################

    def test_BackReferenceReadNode
      assert_prism_eval("$+")
    end

    def test_ClassVariableReadNode
      assert_prism_eval("class Prism::TestCompilePrism; @@pit = 1; @@pit; end")
    end

    def test_ConstantPathNode
      assert_prism_eval("Prism::TestCompilePrism")
    end

    def test_ConstantReadNode
      assert_prism_eval("Prism")
    end

    Z = 1

    def test_DefinedNode
      assert_prism_eval("defined? nil")
      assert_prism_eval("defined? self")
      assert_prism_eval("defined? true")
      assert_prism_eval("defined? false")
      assert_prism_eval("defined? 1")
      assert_prism_eval("defined? 1i")
      assert_prism_eval("defined? 1.0")
      assert_prism_eval("defined? 1..2")
      assert_prism_eval("defined? [A, B, C]")
      assert_prism_eval("defined? [1, 2, 3]")
      assert_prism_eval("defined?({ a: 1 })")
      assert_prism_eval("defined? 'str'")
      assert_prism_eval('defined?("#{expr}")')
      assert_prism_eval("defined? :sym")
      assert_prism_eval("defined? /foo/")
      assert_prism_eval('defined?(/#{1}/)')
      assert_prism_eval("defined? -> { 1 + 1 }")
      assert_prism_eval("defined? a && b")
      assert_prism_eval("defined? a || b")
      assert_prism_eval("defined? __ENCODING__")
      assert_prism_eval("defined? __FILE__")
      assert_prism_eval("defined? __LINE__")

      assert_prism_eval("defined? %[1,2,3]")
      assert_prism_eval("defined? %q[1,2,3]")
      assert_prism_eval("defined? %Q[1,2,3]")
      assert_prism_eval("defined? %r[1,2,3]")
      assert_prism_eval("defined? %i[1,2,3]")
      assert_prism_eval("defined? %I[1,2,3]")
      assert_prism_eval("defined? %w[1,2,3]")
      assert_prism_eval("defined? %W[1,2,3]")
      assert_prism_eval("defined? %s[1,2,3]")
      assert_prism_eval("defined? %x[1,2,3]")

      assert_prism_eval("defined? [*b]")
      assert_prism_eval("defined? [[*1..2], 3, *4..5]")
      assert_prism_eval("defined? [a: [:b, :c]]")
      assert_prism_eval("defined? 1 in 1")

      assert_prism_eval("defined? @a")
      assert_prism_eval("defined? $a")
      assert_prism_eval("defined? @@a")
      assert_prism_eval("defined? A")
      assert_prism_eval("defined? ::A")
      assert_prism_eval("defined? A::B")
      assert_prism_eval("defined? A::B::C")
      assert_prism_eval("defined? #{self.class.name}::Z::A")
      assert_prism_eval("defined? yield")
      assert_prism_eval("defined? super")

      assert_prism_eval("defined? X = 1")
      assert_prism_eval("defined? X *= 1")
      assert_prism_eval("defined? X /= 1")
      assert_prism_eval("defined? X &= 1")
      assert_prism_eval("defined? X ||= 1")

      assert_prism_eval("defined? $1")
      assert_prism_eval("defined? $2")
      assert_prism_eval("defined? $`")
      assert_prism_eval("defined? $'")
      assert_prism_eval("defined? $+")

      assert_prism_eval("defined? $X = 1")
      assert_prism_eval("defined? $X *= 1")
      assert_prism_eval("defined? $X /= 1")
      assert_prism_eval("defined? $X &= 1")
      assert_prism_eval("defined? $X ||= 1")

      assert_prism_eval("defined? @@X = 1")
      assert_prism_eval("defined? @@X *= 1")
      assert_prism_eval("defined? @@X /= 1")
      assert_prism_eval("defined? @@X &= 1")
      assert_prism_eval("defined? @@X ||= 1")

      assert_prism_eval("defined? @X = 1")
      assert_prism_eval("defined? @X *= 1")
      assert_prism_eval("defined? @X /= 1")
      assert_prism_eval("defined? @X &= 1")
      assert_prism_eval("defined? @X ||= 1")

      assert_prism_eval("x = 1; defined? x = 1")
      assert_prism_eval("x = 1; defined? x *= 1")
      assert_prism_eval("x = 1; defined? x /= 1")
      assert_prism_eval("x = 1; defined? x &= 1")
      assert_prism_eval("x = 1; defined? x ||= 1")

      assert_prism_eval("if defined? A; end")

      assert_prism_eval("defined?(())")
      assert_prism_eval("defined?(('1'))")

      # method chain starting with self that's truthy
      assert_prism_eval("defined?(self.itself.itself.itself)")

      # method chain starting with self that's false (exception swallowed)
      assert_prism_eval("defined?(self.itself.itself.neat)")

      # single self with method, truthy
      assert_prism_eval("defined?(self.itself)")

      # single self with method, false
      assert_prism_eval("defined?(self.neat!)")

      # method chain implicit self that's truthy
      assert_prism_eval("defined?(itself.itself.itself)")

      # method chain implicit self that's false
      assert_prism_eval("defined?(itself.neat.itself)")

      ## single method implicit self that's truthy
      assert_prism_eval("defined?(itself)")

      ## single method implicit self that's false
      assert_prism_eval("defined?(neatneat)")

      assert_prism_eval("defined?(a(itself))")
      assert_prism_eval("defined?(itself(itself))")

      # Method chain on a constant
      assert_prism_eval(<<~RUBY)
        class PrismDefinedNode
          def m1; end
        end

        defined?(PrismDefinedNode.new.m1)
      RUBY

      assert_prism_eval("defined?(next)")
      assert_prism_eval("defined?(break)")
      assert_prism_eval("defined?(redo)")
      assert_prism_eval("defined?(retry)")

      assert_prism_eval(<<~RUBY)
        class PrismDefinedReturnNode
          def self.m1; defined?(return) end
        end

        PrismDefinedReturnNode.m1
      RUBY

      assert_prism_eval("defined?(begin; 1; end)")

      assert_prism_eval("defined?(defined?(a))")
      assert_prism_eval('defined?(:"#{1}")')
      assert_prism_eval("defined?(`echo #{1}`)")

      assert_prism_eval("defined?(PrismTestSubclass.test_call_and_write_node &&= 1)")
      assert_prism_eval("defined?(PrismTestSubclass.test_call_operator_write_node += 1)")
      assert_prism_eval("defined?(PrismTestSubclass.test_call_or_write_node ||= 1)")
      assert_prism_eval("defined?(Prism::CPAWN &&= 1)")
      assert_prism_eval("defined?(Prism::CPOWN += 1)")
      assert_prism_eval("defined?(Prism::CPOrWN ||= 1)")
      assert_prism_eval("defined?(Prism::CPWN = 1)")
      assert_prism_eval("defined?([0][0] &&= 1)")
      assert_prism_eval("defined?([0][0] += 1)")
      assert_prism_eval("defined?([0][0] ||= 1)")

      assert_prism_eval("defined?(case :a; when :a; 1; else; 2; end)")
      assert_prism_eval("defined?(case [1, 2, 3]; in [1, 2, 3]; 4; end)")
      assert_prism_eval("defined?(class PrismClassA; end)")
      assert_prism_eval("defined?(def prism_test_def_node; end)")
      assert_prism_eval("defined?(for i in [1,2] do; i; end)")
      assert_prism_eval("defined?(if true; 1; end)")
      assert_prism_eval("defined?(/(?<foo>bar)/ =~ 'barbar')")
      assert_prism_eval("defined?(1 => 1)")
      assert_prism_eval("defined?(module M; end)")
      assert_prism_eval("defined?(1.2r)")
      assert_prism_eval("defined?(class << self; end)")
      assert_prism_eval("defined?(while a != 1; end)")
      assert_prism_eval("defined?(until a == 1; end)")
      assert_prism_eval("defined?(unless true; 1; end)")
    end

    def test_GlobalVariableReadNode
      assert_prism_eval("$pit = 1; $pit")
    end

    def test_InstanceVariableReadNode
      assert_prism_eval("class Prism::TestCompilePrism; @pit = 1; @pit; end")
    end

    def test_LocalVariableReadNode
      assert_prism_eval("pit = 1; pit")
    end

    def test_NumberedReferenceReadNode
      assert_prism_eval("$1")
      assert_prism_eval("$99999")
    end

    ############################################################################
    # Writes                                                                   #
    ############################################################################

    def test_ClassVariableAndWriteNode
      assert_prism_eval("class Prism::TestCompilePrism; @@pit = 0; @@pit &&= 1; end")
    end

    def test_ClassVariableOperatorWriteNode
      assert_prism_eval("class Prism::TestCompilePrism; @@pit = 0; @@pit += 1; end")
    end

    def test_ClassVariableOrWriteNode
      assert_prism_eval("class Prism::TestCompilePrism; @@pit = 1; @@pit ||= 0; end")
      assert_prism_eval("class Prism::TestCompilePrism; @@pit = nil; @@pit ||= 1; end")
    end

    def test_ClassVariableWriteNode
      assert_prism_eval("class Prism::TestCompilePrism; @@pit = 1; end")
    end

    def test_ConstantAndWriteNode
      assert_prism_eval("Constant = 1; Constant &&= 1")
    end

    def test_ConstantOperatorWriteNode
      assert_prism_eval("Constant = 1; Constant += 1")
    end

    def test_ConstantOrWriteNode
      assert_prism_eval("Constant = 1; Constant ||= 1")
    end

    def test_ConstantWriteNode
      # We don't call assert_prism_eval directly in this case because we
      # don't want to assign the constant multiple times if we run
      # with `--repeat-count`
      # Instead, we eval manually here, and remove the constant to
      constant_name = "YCT"
      source = "#{constant_name} = 1"
      prism_eval = RubyVM::InstructionSequence.compile_prism(source).eval
      assert_equal prism_eval, 1
      Object.send(:remove_const, constant_name)
    end

    def test_ConstantPathWriteNode
      assert_prism_eval("Prism::CPWN = 1")
      assert_prism_eval("::CPWN = 1")
    end

    def test_ConstantPathAndWriteNode
      assert_prism_eval("Prism::CPAWN = 1; Prism::CPAWN &&= 2")
      assert_prism_eval("Prism::CPAWN &&= 1")
      assert_prism_eval("::CPAWN = 1; ::CPAWN &&= 2")
    end

    def test_ConstantPathOrWriteNode
      assert_prism_eval("Prism::CPOrWN = nil; Prism::CPOrWN ||= 1")
      assert_prism_eval("Prism::CPOrWN ||= 1")
      assert_prism_eval("::CPOrWN = nil; ::CPOrWN ||= 1")
    end

    def test_ConstantPathOperatorWriteNode
      assert_prism_eval("Prism::CPOWN = 0; Prism::CPOWN += 1")
      assert_prism_eval("::CPOWN = 0; ::CPOWN += 1")
    end

    def test_GlobalVariableAndWriteNode
      assert_prism_eval("$pit = 0; $pit &&= 1")
    end

    def test_GlobalVariableOperatorWriteNode
      assert_prism_eval("$pit = 0; $pit += 1")
    end

    def test_GlobalVariableOrWriteNode
      assert_prism_eval("$pit ||= 1")
    end

    def test_GlobalVariableWriteNode
      assert_prism_eval("$pit = 1")
    end

    def test_InstanceVariableAndWriteNode
      assert_prism_eval("@pit = 0; @pit &&= 1")
    end

    def test_InstanceVariableOperatorWriteNode
      assert_prism_eval("@pit = 0; @pit += 1")
    end

    def test_InstanceVariableOrWriteNode
      assert_prism_eval("@pit ||= 1")
    end

    def test_InstanceVariableWriteNode
      assert_prism_eval("class Prism::TestCompilePrism; @pit = 1; end")
    end

    def test_LocalVariableAndWriteNode
      assert_prism_eval("pit = 0; pit &&= 1")
    end

    def test_LocalVariableOperatorWriteNode
      assert_prism_eval("pit = 0; pit += 1")
    end

    def test_LocalVariableOrWriteNode
      assert_prism_eval("pit ||= 1")
    end

    def test_LocalVariableWriteNode
      assert_prism_eval("pit = 1")
      assert_prism_eval(<<-CODE)
        a = 0
        [].each do
          a = 1
        end
        a
      CODE

      assert_prism_eval(<<-CODE)
        a = 1
        d = 1
        [1].each do
          b = 2
          a = 2
          [2].each do
            c = 3
            d = 4
            a = 2
          end
        end
        [a, d]
      CODE
    end

    def test_MatchWriteNode
      assert_prism_eval("/(?<foo>bar)(?<baz>bar>)/ =~ 'barbar'")
      assert_prism_eval("/(?<foo>bar)/ =~ 'barbar'")
    end

    ############################################################################
    # Multi-writes                                                             #
    ############################################################################

    def test_ClassVariableTargetNode
      assert_prism_eval("class Prism::TestCompilePrism; @@pit, @@pit1 = 1; end")
    end

    def test_ConstantTargetNode
      # We don't call assert_prism_eval directly in this case because we
      # don't want to assign the constant multiple times if we run
      # with `--repeat-count`
      # Instead, we eval manually here, and remove the constant to
      constant_names = ["YCT", "YCT2"]
      source = "#{constant_names.join(",")} = 1"
      prism_eval = RubyVM::InstructionSequence.compile_prism(source).eval
      assert_equal prism_eval, 1
      constant_names.map { |name|
        Object.send(:remove_const, name)
      }
    end

    def test_ConstantPathTargetNode
      assert_separately([], <<~'RUBY')
        verbose = $VERBOSE
        # Create some temporary nested constants
        Object.send(:const_set, "MyFoo", Object)
        Object.const_get("MyFoo").send(:const_set, "Bar", Object)

        constant_names = ["MyBar", "MyFoo::Bar", "MyFoo::Bar::Baz"]
        source = "#{constant_names.join(",")} = Object"
        iseq = RubyVM::InstructionSequence.compile_prism(source)
        $VERBOSE = nil
        prism_eval = iseq.eval
        $VERBOSE = verbose
        assert_equal prism_eval, Object
      RUBY
    end

    def test_GlobalVariableTargetNode
      assert_prism_eval("$pit, $pit1 = 1")
    end

    def test_InstanceVariableTargetNode
      assert_prism_eval("class Prism::TestCompilePrism; @pit, @pit1 = 1; end")
    end

    def test_LocalVariableTargetNode
      assert_prism_eval("pit, pit1 = 1")
      assert_prism_eval(<<-CODE)
        a = 1
        [1].each do
          c = 2
          a, b = 2
        end
        a
      CODE
    end

    def test_MultiTargetNode
      assert_prism_eval("a, (b, c) = [1, 2, 3]")
      assert_prism_eval("a, (b, c) = [1, 2, 3]; a")
      assert_prism_eval("a, (b, c) = [1, 2, 3]; b")
      assert_prism_eval("a, (b, c) = [1, 2, 3]; c")
      assert_prism_eval("a, (b, c) = [1, [2, 3]]; c")
      assert_prism_eval("a, (b, *c) = [1, [2, 3]]; c")
      assert_prism_eval("a, (b, *c) = 1, [2, 3]; c")
      assert_prism_eval("a, (b, *) = 1, [2, 3]; b")
      assert_prism_eval("a, (b, *c, d) = 1, [2, 3, 4]; [a, b, c, d]")
      assert_prism_eval("(a, (b, c, d, e), f, g), h = [1, [2, 3]], 4, 5, [6, 7]; c")
    end

    def test_MultiWriteNode
      assert_prism_eval("foo, bar = [1, 2]")
      assert_prism_eval("foo, = [1, 2]")
      assert_prism_eval("foo, *, bar = [1, 2]")
      assert_prism_eval("foo, bar = 1, 2")
      assert_prism_eval("foo, *, bar = 1, 2")
      assert_prism_eval("foo, *, bar = 1, 2, 3, 4")
      assert_prism_eval("a, b, *, d = 1, 2, 3, 4")
      assert_prism_eval("a, b, *, d = 1, 2")
      assert_prism_eval("(a, b), *, c = [1, 3], 4, 5")
      assert_prism_eval("(a, b), *, c = [1, 3], 4, 5; a")
      assert_prism_eval("(a, b), *, c = [1, 3], 4, 5; b")
      assert_prism_eval("(a, b), *, c = [1, 3], 4, 5; c")
      assert_prism_eval("a, *, (c, d) = [1, 3], 4, 5; a")
      assert_prism_eval("a, *, (c, d) = [1, 3], 4, 5; c")
      assert_prism_eval("(a, b, c), *, (d, e) = [1, 3], 4, 5, [6, 7]")
      assert_prism_eval("(a, b, c), *, (d, e) = [1, 3], 4, 5, [6, 7]; b")
      assert_prism_eval("(a, b, c), *, (d, e) = [1, 3], 4, 5, [6, 7]; d")
      assert_prism_eval("((a, *, b), *, (c, *, (d, *, e, f, g))), *, ((h, i, *, j), *, (k, l, m, *, n, o, p), q, r) = 1; a")
      assert_prism_eval("*a = 1; a")
      assert_prism_eval("_, {}[:foo] = 1")
      assert_prism_eval("_, {}[:foo], _ = 1")
      assert_prism_eval("_, {}[:foo], _ = 1")
      assert_prism_eval("_,{}[:foo], _, {}[:bar] = 1")
      assert_prism_eval("* = :foo")
      assert_prism_eval("* = *[]")
      assert_prism_eval("a, * = :foo")


      assert_prism_eval(<<~CODE)
        class Foo
          def bar=(x); end
          def baz=(c); end
        end
        foo = Foo.new
        foo.bar, foo.baz = 1
      CODE
      assert_prism_eval(<<~CODE)
        class Foo
          def bar=(x); end
          def baz=(c); end
        end
        foo = Foo.new
        _, foo.bar, foo.baz = 1
      CODE
      assert_prism_eval(<<~CODE)
        class Foo
          def bar=(x); end
          def baz=(c); end
        end
        foo = Foo.new
        _, foo.bar, _, foo.baz = 1
      CODE

      # Test nested writes with method calls
      assert_prism_eval(<<~RUBY)
        class Foo
          attr_accessor :bar
        end

        a = Foo.new

        (a.bar, a.bar), b = [1], 2
      RUBY
      assert_prism_eval(<<~RUBY)
        h = {}
        (h[:foo], h[:bar]), a = [1], 2
      RUBY
    end

    ############################################################################
    # String-likes                                                             #
    ############################################################################

    def test_EmbeddedStatementsNode
      assert_prism_eval('"foo #{to_s} baz"')
    end

    def test_EmbeddedVariableNode
      assert_prism_eval('class Prism::TestCompilePrism; @pit = 1; "#@pit"; end')
      assert_prism_eval('class Prism::TestCompilePrism; @@pit = 1; "#@@pit"; end')
      assert_prism_eval('$pit = 1; "#$pit"')
    end

    def test_InterpolatedMatchLastLineNode
      assert_prism_eval('$pit = ".oo"; if /"#{$pit}"/mix; end')
    end

    def test_InterpolatedRegularExpressionNode
      assert_prism_eval('$pit = 1; /1 #$pit 1/')
      assert_prism_eval('$pit = 1; /#$pit/i')
      assert_prism_eval('/1 #{1 + 2} 1/')
      assert_prism_eval('/1 #{"2"} #{1 + 2} 1/')
    end

    def test_InterpolatedStringNode
      assert_prism_eval('$pit = 1; "1 #$pit 1"')
      assert_prism_eval('"1 #{1 + 2} 1"')
      assert_prism_eval('"Prism" "::" "TestCompilePrism"')
      assert_prism_eval(<<-'RUBY')
        # frozen_string_literal: true

        !("a""b""#{1}").frozen?
      RUBY
      assert_prism_eval(<<-'RUBY')
        # frozen_string_literal: true

        !("a""#{1}""b").frozen?
      RUBY

      # Test encoding of interpolated strings
      assert_prism_eval(<<~'RUBY')
        "#{"foo"}s".encoding
      RUBY
      assert_prism_eval(<<~'RUBY')
        a = "foo"
        b = "#{a}" << "Bar"
        [a, b, b.encoding]
      RUBY
    end

    def test_concatenated_StringNode
      assert_prism_eval('("a""b").frozen?')
      assert_prism_eval(<<-CODE)
        # frozen_string_literal: true

        ("a""b").frozen?
      CODE
    end

    def test_InterpolatedSymbolNode
      assert_prism_eval('$pit = 1; :"1 #$pit 1"')
      assert_prism_eval(':"1 #{1 + 2} 1"')
    end

    def test_InterpolatedXStringNode
      assert_prism_eval(<<~RUBY)
        def self.`(command) = command * 2
        `echo \#{1}`
      RUBY

      assert_prism_eval(<<~RUBY)
        def self.`(command) = command * 2
        `echo \#{"100"}`
      RUBY
    end

    def test_MatchLastLineNode
      assert_prism_eval("if /foo/; end")
      assert_prism_eval("if /foo/i; end")
      assert_prism_eval("if /foo/x; end")
      assert_prism_eval("if /foo/m; end")
      assert_prism_eval("if /foo/im; end")
      assert_prism_eval("if /foo/mx; end")
      assert_prism_eval("if /foo/xi; end")
      assert_prism_eval("if /foo/ixm; end")
    end

    def test_RegularExpressionNode
      assert_prism_eval('/pit/')
      assert_prism_eval('/pit/i')
      assert_prism_eval('/pit/x')
      assert_prism_eval('/pit/m')
      assert_prism_eval('/pit/im')
      assert_prism_eval('/pit/mx')
      assert_prism_eval('/pit/xi')
      assert_prism_eval('/pit/ixm')

      assert_prism_eval('/pit/u')
      assert_prism_eval('/pit/e')
      assert_prism_eval('/pit/s')
      assert_prism_eval('/pit/n')

      assert_prism_eval('/pit/me')
      assert_prism_eval('/pit/ne')

      assert_prism_eval('2.times.map { /#{1}/o }')
      assert_prism_eval('2.times.map { foo = 1; /#{foo}/o }')
    end

    def test_StringNode
      assert_prism_eval('"pit"')
      assert_prism_eval('"a".frozen?')
    end

    def test_StringNode_frozen_string_literal_true
      [
        # Test that string literal is frozen
        <<~RUBY,
          # frozen_string_literal: true
          "a".frozen?
        RUBY
        # Test that two string literals with the same contents are the same string
        <<~RUBY,
          # frozen_string_literal: true
          "hello".equal?("hello")
        RUBY
      ].each do |src|
        assert_prism_eval(src, raw: true)
      end
    end

    def test_StringNode_frozen_string_literal_false
      [
        # Test that string literal is frozen
        <<~RUBY,
          # frozen_string_literal: false
          !"a".frozen?
        RUBY
        # Test that two string literals with the same contents are the same string
        <<~RUBY,
          # frozen_string_literal: false
          !"hello".equal?("hello")
        RUBY
      ].each do |src|
        assert_prism_eval(src, raw: true)
      end
    end

    def test_StringNode_frozen_string_literal_default
      # Test that string literal is chilled
      assert_prism_eval('"a".frozen?')

      # Test that two identical chilled string literals aren't the same object
      assert_prism_eval('!"hello".equal?("hello")')
    end

    def test_SymbolNode
      assert_prism_eval(":pit")

      # Test UTF-8 symbol in a US-ASCII file
      assert_prism_eval(<<~'RUBY', raw: true)
        # -*- coding: us-ascii -*-
        :"\u{e9}"
      RUBY

      # Test ASCII-8BIT symbol in a US-ASCII file
      assert_prism_eval(<<~'RUBY', raw: true)
        # -*- coding: us-ascii -*-
        :"\xff"
      RUBY

      # Test US-ASCII symbol in a ASCII-8BIT file
      assert_prism_eval(<<~'RUBY', raw: true)
        # -*- coding: ascii-8bit -*-
        :a
      RUBY
    end

    def test_XStringNode
      assert_prism_eval(<<~RUBY)
        class Prism::TestCompilePrism
          def self.`(command) = command * 2
          `pit`
        end
      RUBY
    end

    ############################################################################
    # Structures                                                               #
    ############################################################################

    def test_ArrayNode
      assert_prism_eval("[]")
      assert_prism_eval("[1, 2, 3]")
      assert_prism_eval("%i[foo bar baz]")
      assert_prism_eval("%w[foo bar baz]")
      assert_prism_eval("[*1..2]")
      assert_prism_eval("[*1..2, 3, 4, *5..6, 7, 8]")
      assert_prism_eval("[*1..2, 3, 4, *5..6, 7, 8, *9..11]")
      assert_prism_eval("[0, *1..2, 3, 4, *5..6, 7, 8, *9..11]")
      assert_prism_eval("[-1, true, 0, *1..2, 3, 4, *5..6, 7, 8, *9..11]")
      assert_prism_eval("a = [1,2]; [0, *a, 3, 4, *5..6, 7, 8, *9..11]")
      assert_prism_eval("[[*1..2], 3, *4..5]")

      elements = Array.new(64) { ":foo" }
      assert_prism_eval("[#{elements.join(", ")}, bar: 1, baz: 2]")

      # Test keyword splat inside of array
      assert_prism_eval("[**{x: 'hello'}]")

      # Test UTF-8 string array literal in a US-ASCII file
      assert_prism_eval(<<~'RUBY', raw: true)
        # -*- coding: us-ascii -*-
        # frozen_string_literal: true
        %W"\u{1f44b} \u{1f409}"
      RUBY
    end

    def test_AssocNode
      assert_prism_eval("{ foo: :bar }")
    end

    def test_AssocSplatNode
      assert_prism_eval("foo = { a: 1 }; { **foo }")
      assert_prism_eval("foo = { a: 1 }; bar = foo; { **foo, b: 2, **bar, c: 3 }")
      assert_prism_eval("foo = { a: 1 }; { b: 2, **foo, c: 3}")

      # Test anonymous AssocSplatNode
      assert_prism_eval(<<~RUBY)
        o = Object.new
        def o.bar(**) = Hash(**)

        o.bar(hello: "world")
      RUBY

      # Test that AssocSplatNode is evaluated before BlockArgumentNode using
      # the splatkw instruction
      assert_prism_eval(<<~RUBY)
        o = Struct.new(:ary) do
          def to_hash
            ary << :to_hash
            {}
          end

          def to_proc
            ary << :to_proc
            -> {}
          end

          def t(...); end
        end.new
        o.ary = []

        o.t(**o, &o)
        o.ary
      RUBY
    end

    def test_HashNode
      assert_prism_eval("{}")
      assert_prism_eval("{ a: :a }")
      assert_prism_eval("{ a: :a, b: :b }")
      assert_prism_eval("a = 1; { a: a }")
      assert_prism_eval("a = 1; { a: }")
      assert_prism_eval("{ to_s: }")
      assert_prism_eval("{ Prism: }")
      assert_prism_eval("[ Prism: [:b, :c]]")
      assert_prism_eval("{ [] => 1}")
    end

    def test_ImplicitNode
      assert_prism_eval("{ to_s: }")
    end

    def test_RangeNode
      assert_prism_eval("1..2")
      assert_prism_eval("1...2")
      assert_prism_eval("..2")
      assert_prism_eval("...2")
      assert_prism_eval("1..")
      assert_prism_eval("1...")
      assert_prism_eval("a1 = 1; a2 = 2; a1..a2")
      assert_prism_eval("a1 = 1; a2 = 2; a1...a2")
      assert_prism_eval("a2 = 2; ..a2")
      assert_prism_eval("a2 = 2; ...a2")
      assert_prism_eval("a1 = 1; a1..")
      assert_prism_eval("a1 = 1; a1...")
      assert_prism_eval("1..2; nil")
      assert_prism_eval("1...2; nil")
      assert_prism_eval("..2; nil")
      assert_prism_eval("...2; nil")
      assert_prism_eval("1..; nil")
      assert_prism_eval("1...; nil")
      assert_prism_eval("a1 = 1; a2 = 2; a1..a2; nil")
      assert_prism_eval("a1 = 1; a2 = 2; a1...a2; nil")
      assert_prism_eval("a2 = 2; ..a2; nil")
      assert_prism_eval("a2 = 2; ...a2; nil")
      assert_prism_eval("a1 = 1; a1..; nil")
      assert_prism_eval("a1 = 1; a1...; nil")
    end

    def test_SplatNode
      assert_prism_eval("*b = []; b")
      assert_prism_eval("*b = [1, 2, 3]; b")
      assert_prism_eval("a, *b = [1, 2, 3]; a")
      assert_prism_eval("a, *b = [1, 2, 3]; b")
      assert_prism_eval("a, *b, c = [1, 2, 3]; a")
      assert_prism_eval("a, *b, c = [1, 2, 3]; b")
      assert_prism_eval("a, *b, c = [1, 2, 3]; c")
      assert_prism_eval("*b, c = [1, 2, 3]; b")
      assert_prism_eval("*b, c = [1, 2, 3]; c")
      assert_prism_eval("a, *, c = [1, 2, 3]; a")
      assert_prism_eval("a, *, c = [1, 2, 3]; c")

      # Test anonymous splat node
      assert_prism_eval(<<~RUBY)
        def self.bar(*) = Array(*)

        bar([1, 2, 3])
      RUBY
    end

    ############################################################################
    # Jumps                                                                    #
    ############################################################################

    def test_AndNode
      assert_prism_eval("true && 1")
      assert_prism_eval("false && 1")
    end

    def test_CaseNode
      assert_prism_eval("case :a; when :a; 1; else; 2; end")
      assert_prism_eval("case :a; when :b; 1; else; 2; end")
      assert_prism_eval("case :a; when :a; 1; else; 2; end")
      assert_prism_eval("case :a; when :a; end")
      assert_prism_eval("case :a; when :b, :c; end")
      assert_prism_eval("case; when :a; end")
      assert_prism_eval("case; when :a, :b; 1; else; 2 end")
      assert_prism_eval("case :a; when :b; else; end")
      assert_prism_eval("b = 1; case :a; when b; else; end")
      assert_prism_eval(<<-CODE)
        def self.prism_test_case_node
          case :a
          when :b
          else
            return 2
          end
          1
        end
        prism_test_case_node
      CODE

      # Test splat in when
      assert_prism_eval(<<~RUBY)
        ary = [1, 2]
        case 1
        when *ary
          :ok
        else
          :ng
        end
      RUBY

      # Test splat in when
      assert_prism_eval(<<~RUBY)
        ary = [1, 2]
        case 1
        when :foo, *ary
          :ok
        else
          :ng
        end
      RUBY

      # Test case without predicate
      assert_prism_eval(<<~RUBY)
        case
        when 1 == 2
          :ng
        else
          :ok
        end
      RUBY

      # test splat with no predicate
      assert_prism_eval(<<~RUBY)
        case
        when *[true]
          :ok
        else
          :ng
        end
      RUBY
    end

    def test_ElseNode
      assert_prism_eval("if false; 0; else; 1; end")
      assert_prism_eval("if true; 0; else; 1; end")
      assert_prism_eval("true ? 1 : 0")
      assert_prism_eval("false ? 0 : 1")
    end

    def test_FlipFlopNode
      assert_prism_eval("not (1 == 1) .. (2 == 2)")
      assert_prism_eval("not (1 == 1) ... (2 == 2)")
    end

    def test_IfNode
      assert_prism_eval("if true; 1; end")
      assert_prism_eval("1 if true")
      assert_prism_eval('a = b = 1; if a..b; end')
      assert_prism_eval('if "a".."b"; end')
      assert_prism_eval('if "a"..; end')
      assert_prism_eval('if .."b"; end')
      assert_prism_eval('if ..1; end')
      assert_prism_eval('if 1..; end')
      assert_prism_eval('if 1..2; end')
      assert_prism_eval('if true or true; end');
    end

    def test_OrNode
      assert_prism_eval("true || 1")
      assert_prism_eval("false || 1")
    end

    def test_UnlessNode
      assert_prism_eval("1 unless true")
      assert_prism_eval("1 unless false")
      assert_prism_eval("unless true; 1; end")
      assert_prism_eval("unless false; 1; end")
    end

    def test_UntilNode
      assert_prism_eval("a = 0; until a == 1; a = a + 1; end")

      # Test UntilNode in rescue
      assert_prism_eval(<<~RUBY)
        o = Object.new
        o.instance_variable_set(:@ret, [])
        def o.foo = @ret << @ret.length
        def o.bar = @ret.length > 3
        begin
          raise
        rescue
          o.foo until o.bar
        end
        o.instance_variable_get(:@ret)
      RUBY
    end

    def test_WhileNode
      assert_prism_eval("a = 0; while a != 1; a = a + 1; end")

      # Test WhileNode in rescue
      assert_prism_eval(<<~RUBY)
        o = Object.new
        o.instance_variable_set(:@ret, [])
        def o.foo = @ret << @ret.length
        def o.bar = @ret.length < 3
        begin
          raise
        rescue
          o.foo while o.bar
        end
        o.instance_variable_get(:@ret)
      RUBY
    end

    def test_ForNode
      assert_prism_eval("for i in [1,2] do; i; end")
      assert_prism_eval("for @i in [1,2] do; @i; end")
      assert_prism_eval("for $i in [1,2] do; $i; end")

      assert_prism_eval("for foo, in  [1,2,3] do end")

      assert_prism_eval("for i, j in {a: 'b'} do; i; j; end")

      # Test splat node as index in for loop
      assert_prism_eval("for *x in [[1,2], [3,4]] do; x; end")
    end

    ############################################################################
    #  Throws                                                                  #
    ############################################################################

    def test_BeginNode
      assert_prism_eval("begin; 1; end")
      assert_prism_eval("begin; end; 1")
    end

    def test_BreakNode
      assert_prism_eval("while true; break; end")
      assert_prism_eval("while true; break 1; end")
      assert_prism_eval("while true; break 1, 2; end")

      assert_prism_eval("[].each { break }")
      assert_prism_eval("[true].map { break }")
    end

    def test_ensure_in_methods
      assert_prism_eval(<<-CODE)
def self.m
  a = []
ensure
  a << 5
  return a
end
m
      CODE
    end

    def test_break_runs_ensure
      assert_prism_eval(<<-CODE)
a = []
while true
  begin
    break
  ensure
    a << 1
  end
end
a
      CODE
    end

    def test_EnsureNode
      assert_prism_eval("begin; 1; ensure; 2; end")
      assert_prism_eval("begin; 1; begin; 3; ensure; 4; end; ensure; 2; end")
      assert_prism_eval(<<-CODE)
        begin
          a = 2
        ensure
        end
      CODE
      assert_prism_eval(<<-CODE)
        begin
          a = 2
        ensure
          a = 3
        end
        a
      CODE

      # Test that ensure block only evaluated once
      assert_prism_eval(<<~RUBY)
        res = []
        begin
          begin
            raise
          ensure
            res << $!.to_s
          end
        rescue
          res
        end
      RUBY

      assert_prism_eval(<<-CODE)
        a = 1
        begin
          a = 2
        ensure
          a = 3
        end
        a
      CODE
      assert_prism_eval(<<-CODE)
        a = 1
        begin
          b = 2
        ensure
          c = 3
        end
        a + b + c
      CODE
      assert_prism_eval(<<~CODE)
        foo = 1
        begin
        ensure
          begin
          ensure
            foo.nil?
          end
        end
      CODE
      assert_prism_eval(<<~CODE)
        def test
        ensure
          {}.each do |key, value|
            {}[key] = value
          end
        end
      CODE
      assert_prism_eval(<<~CODE)
        def test
          a = 1
        ensure
          {}.each do |key, value|
            {}[key] = a
          end
        end
      CODE
      assert_prism_eval(<<-CODE)
        def self.prism_test_ensure_node
          begin
          ensure
          end
          return
        end
        prism_test_ensure_node
      CODE

      # Test empty ensure block
      assert_prism_eval(<<~RUBY)
        res = []

        begin
          begin
            raise
          ensure
          end
        rescue
          res << "rescue"
        end

        res
      RUBY

      # Bug #21001
      assert_prism_eval(<<~RUBY)
        RUN_ARRAY = [1,2]

        MAP_PROC = Proc.new do |&blk|
          block_results = []
          RUN_ARRAY.each do |value|
            block_value = blk.call(value)
            block_results.push block_value
          end
          block_results
        ensure
          next block_results
        end

        MAP_PROC.call do |value|
          break if value > 1
          next value
        end
      RUBY
    end

    def test_NextNode
      assert_prism_eval("2.times do |i|; next if i == 1; end")

      assert_prism_eval(<<-CODE)
        res = []
        i = 0
        while i < 5
          i += 1
          next if i == 3
          res << i
        end
        res
      CODE

      assert_prism_eval(<<-CODE)
        res = []
        (1..5).each do |i|
          next if i.even?
          res << i
        end
        res
      CODE

      assert_prism_eval(<<-CODE)
        (1..5).map do |i|
          next i, :even if i.even?
          i
        end
      CODE

      assert_prism_eval(<<-CODE)
        res = []
        i = 0
        begin
          i += 1
          next if i == 3
          res << i
        end while i < 5
        res
      CODE

      assert_prism_eval(<<-CODE)
        while false
          begin
          ensure
          end
          next
        end
      CODE

      assert_prism_eval(<<~CODE)
        [].each do
          begin
          rescue
            next
          end
        end
      CODE
    end

    def test_RedoNode
      assert_prism_eval(<<-CODE)
        counter = 0

        5.times do |i|
          counter += 1
          if i == 2 && counter < 3
            redo
          end
        end
      CODE

      assert_prism_eval(<<-CODE)
        for i in 1..5
          if i == 3
            i = 0
            redo
          end
        end
      CODE

      assert_prism_eval(<<-CODE)
        i = 0
        begin
          i += 1
          redo if i == 3
        end while i < 5
      CODE
    end

    def test_RescueNode
      assert_prism_eval("begin; 1; rescue; 2; end")
      assert_prism_eval(<<~CODE)
        begin
         1
        rescue SyntaxError
        2
        end
      CODE
      assert_prism_eval(<<~CODE)
        begin
          1
          raise 'boom'
        rescue StandardError
          2
        end
      CODE
      assert_prism_eval(<<~CODE)
        begin
          a = 1
        rescue StandardError => e
        end
      CODE
      assert_prism_eval(<<~CODE)
        begin
          raise StandardError
        rescue StandardError => e
        end
      CODE
      assert_prism_eval(<<~CODE)
        begin
          1
        rescue StandardError => e
          e
        rescue SyntaxError => f
          f
        else
          4
        end
      CODE
      assert_prism_eval(<<-CODE)
        begin
          a = 2
        rescue
          a = 3
        end
        a
      CODE
      assert_prism_eval(<<-CODE)
        a = 1
        begin
          a = 2
        rescue
          a = 3
        end
        a
      CODE
      assert_prism_eval(<<-CODE)
        a = 1
        begin
          b = 2
          raise "bang"
        rescue
          c = 3
        end
        a + b + c
      CODE
      assert_prism_eval("begin; rescue; end")

      assert_prism_eval(<<~CODE)
        begin
        rescue
          args.each do |key, value|
            tmp[key] = 1
          end
        end
      CODE
      assert_prism_eval(<<~CODE)
        10.times do
          begin
          rescue
            break
          end
        end
      CODE

      # Test RescueNode with ElseNode
      assert_prism_eval(<<~RUBY)
        calls = []
        begin
          begin
          rescue RuntimeError
            calls << 1
          else
            calls << 2
            raise RuntimeError
          end
        rescue RuntimeError
        end

        calls
      RUBY
    end

    def test_RescueModifierNode
      assert_prism_eval("1.nil? rescue false")
      assert_prism_eval("1.nil? rescue 1")
      assert_prism_eval("raise 'bang' rescue nil")
      assert_prism_eval("raise 'bang' rescue a = 1; a.nil?")
      assert_prism_eval("a = 0 rescue (a += 1 && retry if a <= 1)")
    end

    def test_RetryNode
      assert_prism_eval(<<~CODE)
        a = 1
        begin
          a
          raise "boom"
        rescue
          a += 1
          retry unless a > 1
        ensure
          a = 3
        end
      CODE

      assert_prism_eval(<<~CODE)
        begin
        rescue
          foo = 2
          retry
        end
      CODE

      assert_prism_eval(<<~CODE)
        begin
          a = 2
        rescue
          retry
        end
      CODE
    end

    def test_ReturnNode
      assert_prism_eval(<<-CODE)
        def self.prism_test_return_node
          return 1
        end
        prism_test_return_node
      CODE

      assert_prism_eval(<<-CODE)
        def self.prism_test_return_node
          return 1, 2
        end
        prism_test_return_node
      CODE

      assert_prism_eval(<<-CODE)
        def self.prism_test_return_node
          [1].each do |e|
            return true
          end
        end
        prism_test_return_node
      CODE

      assert_prism_eval(<<-CODE)
        def self.prism_test_return_node
          [1].map do |i|
            return i if i == 1
            2
          end
        end
        prism_test_return_node
      CODE

      assert_prism_eval(<<-CODE)
        def self.prism_test_return_node(*args, **kwargs)
          return *args, *args, **kwargs
        end
        prism_test_return_node(1, foo: 0)
      CODE
    end

    ############################################################################
    # Scopes/statements                                                        #
    ############################################################################

    def test_BlockNode
      assert_prism_eval("[1, 2, 3].each { |num| num }")

      assert_prism_eval("[].tap { _1 }")

      assert_prism_eval("[].each { |a,| }")
      assert_prism_eval("[[1, 2, 3]].map { |_, _, a| a }")
      assert_prism_eval("[[1, 2, 3]].map { |_, a| a }")

      assert_prism_eval("[[]].map { |a| a }")
      assert_prism_eval("[[]].map { |a| a }")
      assert_prism_eval("[[]].map { |a, &block| a }")
      assert_prism_eval("[[]].map { |a, &block| a }")
      assert_prism_eval("[{}].map { |a,| }")
      assert_prism_eval("[[]].map { |a,b=1| a }")
      assert_prism_eval("[{}].map { |a,| }")
      assert_prism_eval("[{}].map { |a| a }")

      # Test blocks with MultiTargetNode
      assert_prism_eval("[[1, 2]].each.map { |(a), (b)| [a, b] }")
    end

    def test_ClassNode
      assert_prism_eval("class PrismClassA; end")
      assert_prism_eval("class PrismClassA; end; class PrismClassB < PrismClassA; end")
      assert_prism_eval("class PrismClassA; end; class PrismClassA::PrismClassC; end")
      assert_prism_eval(<<-HERE
        class PrismClassA; end
        class PrismClassA::PrismClassC; end
        class PrismClassB; end
        class PrismClassB::PrismClassD < PrismClassA::PrismClassC; end
      HERE
      )
    end

    # Many of these tests are versions of tests at bootstraptest/test_method.rb
    def test_DefNode
      assert_prism_eval("def prism_test_def_node; end")
      assert_prism_eval("a = Object.new; def a.prism_singleton; :ok; end; a.prism_singleton")
      assert_prism_eval("def self.prism_test_def_node() 1 end; prism_test_def_node()")
      assert_prism_eval("def self.prism_test_def_node(a,b) [a, b] end; prism_test_def_node(1,2)")
      assert_prism_eval("def self.prism_test_def_node(a,x=7,y=1) x end; prism_test_def_node(7,1)")
      assert_prism_eval("def self.prism_test_def_node(a = 1); x = 2; end; prism_test_def_node")

      # rest argument
      assert_prism_eval("def self.prism_test_def_node(*a) a end; prism_test_def_node().inspect")
      assert_prism_eval("def self.prism_test_def_node(*a) a end; prism_test_def_node(1).inspect")
      assert_prism_eval("def self.prism_test_def_node(x,y,*a) a end; prism_test_def_node(7,7,1,2).inspect")
      assert_prism_eval("def self.prism_test_def_node(x,y=7,*a) a end; prism_test_def_node(7).inspect")
      assert_prism_eval("def self.prism_test_def_node(x,y,z=7,*a) a end; prism_test_def_node(7,7).inspect")
      assert_prism_eval("def self.prism_test_def_node(x,y,z=7,zz=7,*a) a end; prism_test_def_node(7,7,7).inspect")

      # keyword arguments
      assert_prism_eval("def self.prism_test_def_node(a: 1, b: 2, c: 4) a + b + c; end; prism_test_def_node(a: 2)")
      assert_prism_eval("def self.prism_test_def_node(a: 1, b: 2, c: 4) a + b + c; end; prism_test_def_node(b: 3)")
      assert_prism_eval(<<-CODE)
        def self.prism_test_def_node(x = 1, y, a: 8, b: 2, c: 4)
          a + b + c + x + y
        end
        prism_test_def_node(10, b: 3)
      CODE
      assert_prism_eval(<<-CODE)
        def self.prism_test_def_node(a: [])
          a
        end
        prism_test_def_node
      CODE

      # block arguments
      assert_prism_eval("def self.prism_test_def_node(&block) block end; prism_test_def_node{}.class")
      assert_prism_eval("def self.prism_test_def_node(&block) block end; prism_test_def_node().inspect")
      assert_prism_eval("def self.prism_test_def_node(a,b=7,*c,&block) b end; prism_test_def_node(7,1).inspect")
      assert_prism_eval("def self.prism_test_def_node(a,b=7,*c,&block) c end; prism_test_def_node(7,7,1).inspect")

      # splat
      assert_prism_eval("def self.prism_test_def_node(a) a end; prism_test_def_node(*[1])")
      assert_prism_eval("def self.prism_test_def_node(x,a) a end; prism_test_def_node(7,*[1])")
      assert_prism_eval("def self.prism_test_def_node(x,y,a) a end; prism_test_def_node(7,7,*[1])")
      assert_prism_eval("def self.prism_test_def_node(x,y,a,b,c) a end; prism_test_def_node(7,7,*[1,7,7])")

      # recursive call
      assert_prism_eval("def self.prism_test_def_node(n) n == 0 ? 1 : prism_test_def_node(n-1) end; prism_test_def_node(5)")

      # instance method
      assert_prism_eval("class PrismTestDefNode; def prism_test_def_node() 1 end end;  PrismTestDefNode.new.prism_test_def_node")
      assert_prism_eval("class PrismTestDefNode; def prism_test_def_node(*a) a end end;  PrismTestDefNode.new.prism_test_def_node(1).inspect")

      # block argument
      assert_prism_eval(<<-CODE)
        def self.prism_test_def_node(&block) prism_test_def_node2(&block) end
        def self.prism_test_def_node2() yield 1 end
        prism_test_def_node2 {|a| a }
      CODE

      # multi argument
      assert_prism_eval(<<-CODE)
        def self.prism_test_def_node(a, (b, *c, d))
          [a, b, c, d]
        end
        prism_test_def_node("a", ["b", "c", "d"])
      CODE
      assert_prism_eval(<<-CODE)
        def self.prism_test_def_node(a, (b, c, *))
          [a, b, c]
        end
        prism_test_def_node("a", ["b", "c"])
      CODE
      assert_prism_eval(<<-CODE)
        def self.prism_test_def_node(a, (*, b, c))
          [a, b, c]
        end
        prism_test_def_node("a", ["b", "c"])
      CODE

      # recursive multis
      assert_prism_eval(<<-CODE)
        def self.prism_test_def_node(a, (b, *c, (d, *e, f)))
          [a, b, c, d, d, e, f]
        end
        prism_test_def_node("a", ["b", "c", ["d", "e", "f"]])
      CODE

      # Many arguments
      assert_prism_eval(<<-CODE)
        def self.prism_test_def_node(a, (b, *c, d), e = 1, *f, g, (h, *i, j),  k:, l: 1, **m)
          [a, b, c, d, e, f, g, h, i, j, k, l, m]
        end
        prism_test_def_node(
          "a",
          ["b", "c1", "c2", "d"],
          "e",
          "f1", "f2",
          "g",
          ["h", "i1", "i2", "j"],
          k: "k",
          l: "l",
          m1: "m1",
          m2: "m2"
        )
      CODE
    end

    def test_pow_parameters
      assert_prism_eval("def self.m(a, **); end; method(:m).parameters")
    end

    def test_star_parameters
      assert_prism_eval("def self.m(a, *, b); end; method(:m).parameters")
    end

    def test_repeated_block_params
      assert_prism_eval("def self.x(&blk); blk; end; x { |_, _, _ = 1, *_, _:, _: 2, **_, &_| }.parameters")
    end

    def test_repeated_proc_params
      assert_prism_eval("proc {|_, _, _ = 1, *_, _:, _: 2, **_, &_| }.parameters")
    end

    def test_forward_parameters_block
      assert_prism_eval("def self.m(&); end; method(:m).parameters")
    end

    def test_forward_parameters
      assert_prism_eval("def self.m(...); end; method(:m).parameters")
    end

    def test_repeated_block_underscore
      assert_prism_eval("def self.m(_, **_, &_); _; end; method(:m).parameters")
    end

    def test_repeated_kw_rest_underscore
      assert_prism_eval("def self.m(_, **_); _; end; method(:m).parameters")
    end

    def test_repeated_required_keyword_underscore
      assert_prism_eval("def self.m(_, _, *_, _, _:); _; end; method(:m).parameters")
      assert_prism_eval("def self.m(_, _, *_, _, _:, _: 2); _; end; method(:m).parameters")
    end

    def test_repeated_required_post_underscore
      assert_prism_eval("def self.m(_, _, *_, _); _; end; method(:m).parameters")
    end

    def test_repeated_splat_underscore
      assert_prism_eval("def self.m(_, _, _ = 1, _ = 2, *_); end; method(:m).parameters")
    end

    def test_repeated_optional_underscore
      assert_prism_eval("def self.m(a, _, _, _ = 1, _ = 2, b); end; method(:m).parameters")
    end

    def test_repeated_required_underscore
      assert_prism_eval("def self.m(a, _, _, b); end; method(:m).parameters")
    end

    def test_locals_in_parameters
      assert_prism_eval("def self.m(a = b = c = 1); [a, b, c]; end; self.m")
    end

    def test_trailing_comma_on_block
      assert_prism_eval("def self.m; yield [:ok]; end; m {|v0,| v0 }")
    end

    def test_complex_default_params
      assert_prism_eval("def self.foo(a:, b: '2'.to_i); [a, b]; end; foo(a: 1)")
      assert_prism_eval("def self.foo(a:, b: 2, c: '3'.to_i); [a, b, c]; end; foo(a: 1)")
    end

    def test_numbered_params
      assert_prism_eval("[1, 2, 3].then { _3 }")
      assert_prism_eval("1.then { one = 1; one + _1 }")
    end

    def test_rescue_with_ensure
      assert_prism_eval(<<-CODE)
begin
  begin
    raise "a"
  rescue
    raise "b"
  ensure
    raise "c"
  end
rescue => e
  e.message
end
      CODE
    end

    def test_required_kwarg_ordering
      assert_prism_eval("def self.foo(a: 1, b:); [a, b]; end; foo(b: 2)")
    end

    def test_trailing_keyword_method_params
      # foo(1, b: 2, c: 3) # argc -> 3
      assert_prism_eval("def self.foo(a, b:, c:); [a, b, c]; end; foo(1, b: 2, c: 3)")
    end

    def test_keyword_method_params_only
      # foo(a: 1, b: 2) # argc -> 2
      assert_prism_eval("def self.foo(a:, b:); [a, b]; end; foo(a: 1, b: 2)")
    end

    def test_keyword_method_params_with_splat
      # foo(a: 1, **b) # argc -> 1
      assert_prism_eval("def self.foo(a:, b:); [a, b]; end; b = { b: 2 }; foo(a: 1, **b)")
    end

    def test_positional_and_splat_keyword_method_params
      # foo(a, **b) # argc -> 2
      assert_prism_eval("def self.foo(a, b); [a, b]; end; b = { b: 2 }; foo(1, **b)")
    end

    def test_positional_and_splat_method_params
      # foo(a, *b, c, *d, e) # argc -> 2
      assert_prism_eval("def self.foo(a, b, c, d, e); [a, b, c, d, e]; end; b = [2]; d = [4]; foo(1, *b, 3, *d, 5)")
    end

    def test_positional_with_splat_and_splat_keyword_method_params
      # foo(a, *b, c, *d, **e) # argc -> 3
      assert_prism_eval("def self.foo(a, b, c, d, e); [a, b, c, d, e]; end; b = [2]; d = [4]; e = { e: 5 }; foo(1, *b, 3, *d, **e)")
    end

    def test_positional_with_splat_and_keyword_method_params
      # foo(a, *b, c, *d, e:) # argc -> 3
      assert_prism_eval("def self.foo(a, b, c, d, e:); [a, b, c, d, e]; end; b = [2]; d = [4]; foo(1, *b, 3, *d, e: 5)")
    end

    def test_leading_splat_and_keyword_method_params
      # foo(*a, b:) # argc -> 2
      assert_prism_eval("def self.foo(a, b:); [a, b]; end; a = [1]; foo(*a, b: 2)")
    end

    def test_repeated_method_params
      assert_prism_eval("def self.foo(_a, _a); _a; end; foo(1, 2)")
    end

    def test_splat_params_with_no_lefties
      assert_prism_eval("def self.foo(v, (*)); v; end; foo(1, [2, 3, 4])")
    end

    def test_method_parameters
      assert_prism_eval(<<-CODE)
        def self.prism_test_method_parameters(a, b=1, *c, d:, e: 2, **f, &g)
        end

        method(:prism_test_method_parameters).parameters
      CODE

      assert_prism_eval(<<-CODE)
        def self.prism_test_method_parameters(d:, e: 2, **f, &g)
        end

        method(:prism_test_method_parameters).parameters
      CODE

      assert_prism_eval(<<-CODE)
        def self.prism_test_method_parameters(**f, &g)
        end

        method(:prism_test_method_parameters).parameters
      CODE

      assert_prism_eval(<<-CODE)
        def self.prism_test_method_parameters(&g)
        end

        method(:prism_test_method_parameters).parameters
      CODE
    end

    def test_LambdaNode
      assert_prism_eval("-> { to_s }.call")
    end

    def test_LambdaNode_with_multiline_args
      assert_prism_eval(<<-CODE)
        -> (a,
            b) {
              a + b
            }.call(1, 2)
      CODE
    end

    def test_ModuleNode
      assert_prism_eval("module M; end")
      assert_prism_eval("module M::N; end")
      assert_prism_eval("module ::O; end")
    end

    def test_ParenthesesNode
      assert_prism_eval("()")
      assert_prism_eval("(1)")
    end

    def test_PreExecutionNode
      assert_prism_eval("BEGIN { a = 1 }; 2", raw: true)
      assert_prism_eval("b = 2; BEGIN { a = 1 }; a + b", raw: true)
    end

    def test_PostExecutionNode
      assert_prism_eval("END { 1 }")
      assert_prism_eval("END { @b }; @b = 1")
      assert_prism_eval("END { @b; 0 }; @b = 1")
      assert_prism_eval("foo = 1; END { foo.nil? }")
      assert_prism_eval("foo = 1; END { END { foo.nil? }}")
    end

    def test_ProgramNode
      assert_prism_eval("")
      assert_prism_eval("1")
    end

    def test_SingletonClassNode
      assert_prism_eval("class << self; end")
    end

    def test_StatementsNode
      assert_prism_eval("1")
    end

    def test_YieldNode
      assert_prism_eval("def prism_test_yield_node; yield; end")
      assert_prism_eval("def prism_test_yield_node; yield 1, 2; end")
      assert_prism_eval("def prism_test_yield_node; yield **kw if condition; end")

      # Test case where there's a call directly after the yield call
      assert_prism_eval("def prism_test_yield_node; yield; 1; end")
      assert_prism_eval("def prism_test_yield_node; yield 1, 2; 1; end")
    end

    ############################################################################
    #  Calls / arguments                                                       #
    ############################################################################

    def test_ArgumentsNode
      # assert_prism_eval("[].push 1")
    end

    def test_BlockArgumentNode
      assert_prism_eval("1.then(&:to_s)")

      # Test anonymous block forwarding
      assert_prism_eval(<<~RUBY)
        o = Object.new
        def o.foo(&) = yield
        def o.bar(&) = foo(&)

        o.bar { :ok }
      RUBY
    end

    def test_BlockLocalVariableNode
      assert_prism_eval(<<-CODE
        pm_var = "outer scope variable"

        1.times { |;pm_var| pm_var = "inner scope variable"; pm_var }
      CODE
      )

      assert_prism_eval(<<-CODE
        pm_var = "outer scope variable"

        1.times { |;pm_var| pm_var = "inner scope variable"; pm_var }
        pm_var
      CODE
      )
    end

    def test_CallNode
      assert_prism_eval("to_s")

      # with arguments
      assert_prism_eval("eval '1'")

      # with arguments and popped
      assert_prism_eval("eval '1'; 1")

      # With different types of calling arguments
      assert_prism_eval(<<-CODE)
        def self.prism_test_call_node_double_splat(**); end
        prism_test_call_node_double_splat(b: 1, **{})
      CODE
      assert_prism_eval(<<-CODE)
        prism_test_call_node_double_splat(:b => 1)
      CODE

      assert_prism_eval(<<-CODE)
        def self.prism_test_call_node_splat(*); end
        prism_test_call_node_splat(*[], 1)
      CODE

      assert_prism_eval("prism_test_call_node_splat(*[], 1, 2)")

      assert_prism_eval(<<~RUBY)
        def self.prism_test_call_node_splat_and_double_splat(a, b, **opts); end
        prism_test_call_node_splat_and_double_splat(*[1], 2, **{})
      RUBY

      assert_prism_eval(<<-CODE)
        class Foo
          def []=(a, b)
            1234
          end
        end

        def self.foo(i, j)
          tbl = Foo.new
          tbl[i] = j
        end
        foo(1, 2)
      CODE

      assert_prism_eval(<<-CODE)
        class Foo
          def i=(a)
            1234
          end
        end

        def self.foo(j)
          tbl = Foo.new
          tbl.i = j
        end
        foo(1)
      CODE

      assert_prism_eval(<<-CODE)
        foo = Object.new
        def foo.[]=(k,v); 42; end
        foo.[]=(1,2)
      CODE

      # With splat inside of []=
      assert_prism_eval(<<~RUBY)
        obj = Object.new
        def obj.[]=(a, b); 10; end
        obj[*[1]] = 3
      RUBY

      assert_prism_eval(<<-CODE)
        def self.prism_opt_var_trail_hash(a = nil, *b, c, **d); end
        prism_opt_var_trail_hash("a")
        prism_opt_var_trail_hash("a", c: 1)
        prism_opt_var_trail_hash("a", "b")
        prism_opt_var_trail_hash("a", "b", "c")
        prism_opt_var_trail_hash("a", "b", "c", c: 1)
        prism_opt_var_trail_hash("a", "b", "c", "c" => 0, c: 1)
      CODE

      assert_prism_eval(<<-CODE)
        def self.foo(*args, **kwargs) = [args, kwargs]

        [
          foo(2 => 3),
          foo([] => 42),
          foo(a: 42, b: 61),
          foo(1, 2, 3, a: 42, "b" => 61),
          foo(:a => 42, :b => 61),
        ]
      CODE

      assert_prism_eval(<<-CODE)
        class PrivateMethod
          def initialize
            self.instance_var
          end
          private
          attr_accessor :instance_var
        end
        pm = PrivateMethod.new
        pm.send(:instance_var)
      CODE

      # Testing safe navigation operator
      assert_prism_eval(<<-CODE)
        def self.test_prism_call_node
          if [][0]&.first
            1
          end
        end
        test_prism_call_node
      CODE

      # Specialized instructions
      assert_prism_eval(%{-"literal"})
      assert_prism_eval(%{"literal".freeze})
    end

    def test_CallAndWriteNode
      assert_prism_eval(<<-CODE
        class PrismTestSubclass; end
        def PrismTestSubclass.test_call_and_write_node; end;
        PrismTestSubclass.test_call_and_write_node &&= 1
      CODE
      )

      assert_prism_eval(<<-CODE
        def PrismTestSubclass.test_call_and_write_node
          "str"
        end
        def PrismTestSubclass.test_call_and_write_node=(val)
          val
        end
        PrismTestSubclass.test_call_and_write_node &&= 1
      CODE
      )

      assert_prism_eval(<<-CODE
        def self.test_call_and_write_node; end;
        self.test_call_and_write_node &&= 1
      CODE
      )

      assert_prism_eval(<<-CODE
        def self.test_call_and_write_node
          "str"
        end
        def self.test_call_and_write_node=(val)
          val
        end
        self.test_call_and_write_node &&= 1
      CODE
      )

      assert_prism_eval(<<-CODE)
        def self.test_prism_call_node; end
        def self.test_prism_call_node=(val)
          val
        end
        self&.test_prism_call_node &&= 1
      CODE

      assert_prism_eval(<<-CODE)
        def self.test_prism_call_node
          2
        end
        def self.test_prism_call_node=(val)
          val
        end
        self&.test_prism_call_node &&= 1
      CODE
    end

    def test_CallOrWriteNode
      assert_prism_eval(<<-CODE
        class PrismTestSubclass; end
        def PrismTestSubclass.test_call_or_write_node; end;
        def PrismTestSubclass.test_call_or_write_node=(val)
          val
        end
        PrismTestSubclass.test_call_or_write_node ||= 1
      CODE
      )

      assert_prism_eval(<<-CODE
        def PrismTestSubclass.test_call_or_write_node
          "str"
        end
        PrismTestSubclass.test_call_or_write_node ||= 1
      CODE
      )

      assert_prism_eval(<<-CODE
        def self.test_call_or_write_node; end;
        def self.test_call_or_write_node=(val)
          val
        end
        self.test_call_or_write_node ||= 1
      CODE
      )

      assert_prism_eval(<<-CODE
        def self.test_call_or_write_node
          "str"
        end
        self.test_call_or_write_node ||= 1
      CODE
      )

      assert_prism_eval(<<-CODE)
        def self.test_prism_call_node
          2
        end
        def self.test_prism_call_node=(val)
          val
        end
        self&.test_prism_call_node ||= 1
      CODE

      assert_prism_eval(<<-CODE)
        def self.test_prism_call_node; end
        def self.test_prism_call_node=(val)
          val
        end
        self&.test_prism_call_node ||= 1
      CODE
    end

    def test_CallOperatorWriteNode
      assert_prism_eval(<<-CODE
        class PrismTestSubclass; end
        def PrismTestSubclass.test_call_operator_write_node
          2
        end
        def PrismTestSubclass.test_call_operator_write_node=(val)
          val
        end
        PrismTestSubclass.test_call_operator_write_node += 1
      CODE
      )
    end

    def test_ForwardingArgumentsNode
      assert_prism_eval(<<-CODE)
        def prism_test_forwarding_arguments_node(...); end;
        def prism_test_forwarding_arguments_node1(...)
          prism_test_forwarding_arguments_node(...)
        end
      CODE

      assert_prism_eval(<<-CODE)
        def prism_test_forwarding_arguments_node(...); end;
        def prism_test_forwarding_arguments_node1(a, ...)
          prism_test_forwarding_arguments_node(1,2, 3, ...)
        end
      CODE

      assert_prism_eval(<<~RUBY)
        o = Object.new
        def o.bar(a, b, c) = [a, b, c]
        def o.foo(...) = 1.times { bar(...) }

        o.foo(1, 2, 3)
      RUBY
    end

    def test_ForwardingSuperNode
      assert_prism_eval("class Forwarding; def to_s; super; end; end")
      assert_prism_eval("class Forwarding; def eval(code); super { code }; end; end")
      assert_prism_eval(<<-CODE)
        class A
          def initialize(a, b)
          end
        end

        class B < A
          attr_reader :res
          def initialize(a, b, *)
            super
            @res = [a, b]
          end
        end

        B.new(1, 2).res
      CODE
    end

    def test_KeywordHashNode
      assert_prism_eval("[a: [:b, :c]]")
    end

    def test_SuperNode
      assert_prism_eval("def to_s; super 1; end")
      assert_prism_eval("def to_s; super(); end")
      assert_prism_eval("def to_s; super('a', :b, [1,2,3]); end")
      assert_prism_eval("def to_s; super(1, 2, 3, &:foo); end")
    end

    ############################################################################
    # Methods / parameters                                                     #
    ############################################################################

    def test_AliasGlobalVariableNode
      assert_prism_eval("alias $prism_foo $prism_bar")
    end

    def test_AliasMethodNode
      assert_prism_eval("alias :prism_a :to_s")
    end

    def test_BlockParameterNode
      assert_prism_eval("def prism_test_block_parameter_node(&bar) end")
      assert_prism_eval("->(b, c=1, *d, e, &f){}")

      # Test BlockParameterNode with no name
      assert_prism_eval("->(&){}")
      assert_prism_eval("def prism_test_block_parameter_node(&); end")
    end

    def test_BlockParametersNode
      assert_prism_eval("Object.tap { || }")
      assert_prism_eval("[1].map { |num| num }")
      assert_prism_eval("[1].map { |a; b| b = 2; a + b}")

      # Test block parameters with multiple _
      assert_prism_eval(<<~RUBY)
        [[1, 2, 3, 4, 5, 6]].map { |(_, _, _, _, _, _)| _ }
      RUBY
    end

    def test_FowardingParameterNode
      assert_prism_eval("def prism_test_forwarding_parameter_node(...); end")
    end

    def test_KeywordRestParameterNode
      assert_prism_eval("def prism_test_keyword_rest_parameter_node(a, **b); end")
      assert_prism_eval("Object.tap { |**| }")

      # Test that KeywordRestParameterNode creates a copy
      assert_prism_eval(<<~RUBY)
        hash = {}
        o = Object.new
        def o.foo(**a) = a[:foo] = 1

        o.foo(**hash)
        hash
      RUBY
    end

    def test_NoKeywordsParameterNode
      assert_prism_eval("def prism_test_no_keywords(**nil); end")
      assert_prism_eval("def prism_test_no_keywords(a, b = 2, **nil); end")
    end

    def test_OptionalParameterNode
      assert_prism_eval("def prism_test_optional_param_node(bar = nil); end")
    end

    def test_OptionalKeywordParameterNode
      assert_prism_eval("def prism_test_optional_keyword_param_node(bar: nil); end")

      # Test with optional argument and method call in OptionalKeywordParameterNode
      assert_prism_eval(<<~RUBY)
        o = Object.new
        def o.foo = 1
        def o.bar(a = nil, b: foo) = b
        o.bar
      RUBY
    end

    def test_ParametersNode
      assert_prism_eval("def prism_test_parameters_node(bar, baz); end")
      assert_prism_eval("def prism_test_parameters_node(a, b = 2); end")
    end

    def test_RequiredParameterNode
      assert_prism_eval("def prism_test_required_param_node(bar); end")
      assert_prism_eval("def prism_test_required_param_node(foo, bar); end")
    end

    def test_RequiredKeywordParameterNode
      assert_prism_eval("def prism_test_required_param_node(bar:); end")
      assert_prism_eval("def prism_test_required_param_node(foo:, bar:); end")
      assert_prism_eval("-> a, b = 1, c:, d:, &e { a }")
    end

    def test_RestParameterNode
      assert_prism_eval("def prism_test_rest_parameter_node(*a); end")
    end

    def test_UndefNode
      assert_prism_eval("def prism_undef_node_1; end; undef prism_undef_node_1")
      assert_prism_eval(<<-HERE
        def prism_undef_node_2
        end
        def prism_undef_node_3
        end
        undef prism_undef_node_2, prism_undef_node_3
      HERE
      )
      assert_prism_eval(<<-HERE
        def prism_undef_node_4
        end
        undef :'prism_undef_node_#{4}'
      HERE
      )
    end

    ############################################################################
    # Pattern matching                                                         #
    ############################################################################

    def test_AlternationPatternNode
      assert_prism_eval("1 in 1 | 2")
      assert_prism_eval("1 in 2 | 1")
      assert_prism_eval("1 in 2 | 3 | 4 | 1")
      assert_prism_eval("1 in 2 | 3")
    end

    def test_ArrayPatternNode
      assert_prism_eval("[] => []")

      ["in", "=>"].each do |operator|
        ["", "Array"].each do |constant|
          assert_prism_eval("[1, 2, 3] #{operator} #{constant}[1, 2, 3]")

          assert_prism_eval("[1, 2, 3] #{operator} #{constant}[*]")
          assert_prism_eval("[1, 2, 3] #{operator} #{constant}[1, *]")
          assert_prism_eval("[1, 2, 3] #{operator} #{constant}[1, 2, *]")
          assert_prism_eval("[1, 2, 3] #{operator} #{constant}[1, 2, 3, *]")

          assert_prism_eval("[1, 2, 3] #{operator} #{constant}[*foo]")
          assert_prism_eval("[1, 2, 3] #{operator} #{constant}[1, *foo]")
          assert_prism_eval("[1, 2, 3] #{operator} #{constant}[1, 2, *foo]")
          assert_prism_eval("[1, 2, 3] #{operator} #{constant}[1, 2, 3, *foo]")

          assert_prism_eval("[1, 2, 3] #{operator} #{constant}[*, 3]")
          assert_prism_eval("[1, 2, 3] #{operator} #{constant}[*, 2, 3]")
          assert_prism_eval("[1, 2, 3] #{operator} #{constant}[*, 1, 2, 3]")

          assert_prism_eval("[1, 2, 3] #{operator} #{constant}[*foo, 3]")
          assert_prism_eval("[1, 2, 3] #{operator} #{constant}[*foo, 2, 3]")
          assert_prism_eval("[1, 2, 3] #{operator} #{constant}[*foo, 1, 2, 3]")
        end
      end

      assert_prism_eval("begin; Object.new => [1, 2, 3]; rescue NoMatchingPatternError; true; end")
      assert_prism_eval("begin; [1, 2, 3] => Object[1, 2, 3]; rescue NoMatchingPatternError; true; end")
    end

    def test_CapturePatternNode
      assert_prism_eval("[1] => [Integer => foo]")
    end

    def test_CaseMatchNode
      assert_prism_eval(<<~RUBY)
        case [1, 2, 3]
        in [1, 2, 3]
          4
        end
      RUBY

      assert_prism_eval(<<~RUBY)
        case { a: 5, b: 6 }
        in [1, 2, 3]
          4
        in { a: 5, b: 6 }
          7
        end
      RUBY

      assert_prism_eval(<<~RUBY)
        case [1, 2, 3, 4]
        in [1, 2, 3]
          4
        in { a: 5, b: 6 }
          7
        else
        end
      RUBY

      assert_prism_eval(<<~RUBY)
        case [1, 2, 3, 4]
        in [1, 2, 3]
          4
        in { a: 5, b: 6 }
          7
        else
          8
        end
      RUBY

      assert_prism_eval(<<~RUBY)
        case [1, 2, 3]
        in [1, 2, 3] unless to_s
        in [1, 2, 3] if to_s.nil?
        in [1, 2, 3]
          true
        end
      RUBY
    end

    def test_FindPatternNode
      ["in", "=>"].each do |operator|
        ["", "Array"].each do |constant|
          assert_prism_eval("[1, 2, 3, 4, 5] #{operator} #{constant}[*, 1, 2, 3, 4, 5, *]")

          assert_prism_eval("[1, 2, 3, 4, 5] #{operator} #{constant}[*, 1, *]")
          assert_prism_eval("[1, 2, 3, 4, 5] #{operator} #{constant}[*, 3, *]")
          assert_prism_eval("[1, 2, 3, 4, 5] #{operator} #{constant}[*, 5, *]")

          assert_prism_eval("[1, 2, 3, 4, 5] #{operator} #{constant}[*, 1, 2, *]")
          assert_prism_eval("[1, 2, 3, 4, 5] #{operator} #{constant}[*, 2, 3, *]")
          assert_prism_eval("[1, 2, 3, 4, 5] #{operator} #{constant}[*, 3, 4, *]")
          assert_prism_eval("[1, 2, 3, 4, 5] #{operator} #{constant}[*, 4, 5, *]")

          assert_prism_eval("[1, 2, 3, 4, 5] #{operator} #{constant}[*, 1, 2, 3, *]")
          assert_prism_eval("[1, 2, 3, 4, 5] #{operator} #{constant}[*, 2, 3, 4, *]")
          assert_prism_eval("[1, 2, 3, 4, 5] #{operator} #{constant}[*, 3, 4, 5, *]")

          assert_prism_eval("[1, 2, 3, 4, 5] #{operator} #{constant}[*, 1, 2, 3, 4, *]")
          assert_prism_eval("[1, 2, 3, 4, 5] #{operator} #{constant}[*, 2, 3, 4, 5, *]")

          assert_prism_eval("[1, 2, 3, 4, 5] #{operator} #{constant}[*foo, 3, *]")
          assert_prism_eval("[1, 2, 3, 4, 5] #{operator} #{constant}[*foo, 3, 4, *]")
          assert_prism_eval("[1, 2, 3, 4, 5] #{operator} #{constant}[*foo, 3, 4, 5, *]")
          assert_prism_eval("[1, 2, 3, 4, 5] #{operator} #{constant}[*foo, 1, 2, 3, 4, *]")

          assert_prism_eval("[1, 2, 3, 4, 5] #{operator} #{constant}[*, 3, *foo]")
          assert_prism_eval("[1, 2, 3, 4, 5] #{operator} #{constant}[*, 3, 4, *foo]")
          assert_prism_eval("[1, 2, 3, 4, 5] #{operator} #{constant}[*, 3, 4, 5, *foo]")
          assert_prism_eval("[1, 2, 3, 4, 5] #{operator} #{constant}[*, 1, 2, 3, 4, *foo]")

          assert_prism_eval("[1, 2, 3, 4, 5] #{operator} #{constant}[*foo, 3, *bar]")
          assert_prism_eval("[1, 2, 3, 4, 5] #{operator} #{constant}[*foo, 3, 4, *bar]")
          assert_prism_eval("[1, 2, 3, 4, 5] #{operator} #{constant}[*foo, 3, 4, 5, *bar]")
          assert_prism_eval("[1, 2, 3, 4, 5] #{operator} #{constant}[*foo, 1, 2, 3, 4, *bar]")
        end
      end

      assert_prism_eval("[1, [2, [3, [4, [5]]]]] => [*, [*, [*, [*, [*]]]]]")
      assert_prism_eval("[1, [2, [3, [4, [5]]]]] => [1, [2, [3, [4, [5]]]]]")

      assert_prism_eval("begin; Object.new => [*, 2, *]; rescue NoMatchingPatternError; true; end")
      assert_prism_eval("begin; [1, 2, 3] => Object[*, 2, *]; rescue NoMatchingPatternError; true; end")
    end

    def test_HashPatternNode
      assert_prism_eval("{} => {}")

      [["{ ", " }"], ["Hash[", "]"]].each do |(prefix, suffix)|
        assert_prism_eval("{} => #{prefix} **nil #{suffix}")

        assert_prism_eval("{ a: 1, b: 2, c: 3 } => #{prefix} a: 1 #{suffix}")
        assert_prism_eval("{ a: 1, b: 2, c: 3 } => #{prefix} a: 1, b: 2 #{suffix}")
        assert_prism_eval("{ a: 1, b: 2, c: 3 } => #{prefix} b: 2, c: 3 #{suffix}")
        assert_prism_eval("{ a: 1, b: 2, c: 3 } => #{prefix} a: 1, b: 2, c: 3 #{suffix}")

        assert_prism_eval("{ a: 1, b: 2, c: 3 } => #{prefix} ** #{suffix}")
        assert_prism_eval("{ a: 1, b: 2, c: 3 } => #{prefix} a: 1, ** #{suffix}")
        assert_prism_eval("{ a: 1, b: 2, c: 3 } => #{prefix} a: 1, b: 2, ** #{suffix}")
        assert_prism_eval("{ a: 1, b: 2, c: 3 } => #{prefix} b: 2, c: 3, ** #{suffix}")
        assert_prism_eval("{ a: 1, b: 2, c: 3 } => #{prefix} a: 1, b: 2, c: 3, ** #{suffix}")

        assert_prism_eval("{ a: 1, b: 2, c: 3 } => #{prefix} **foo #{suffix}")
        assert_prism_eval("{ a: 1, b: 2, c: 3 } => #{prefix} a: 1, **foo #{suffix}")
        assert_prism_eval("{ a: 1, b: 2, c: 3 } => #{prefix} a: 1, b: 2, **foo #{suffix}")
        assert_prism_eval("{ a: 1, b: 2, c: 3 } => #{prefix} b: 2, c: 3, **foo #{suffix}")
        assert_prism_eval("{ a: 1, b: 2, c: 3 } => #{prefix} a: 1, b: 2, c: 3, **foo #{suffix}")

        assert_prism_eval("{ a: 1 } => #{prefix} a: 1, **nil #{suffix}")
        assert_prism_eval("{ a: 1, b: 2, c: 3 } => #{prefix} a: 1, b: 2, c: 3, **nil #{suffix}")
      end

      assert_prism_eval("{ a: { b: { c: 1 } } } => { a: { b: { c: 1 } } }")
    end

    def test_MatchPredicateNode
      assert_prism_eval("1 in 1")
      assert_prism_eval("1.0 in 1.0")
      assert_prism_eval("1i in 1i")
      assert_prism_eval("1r in 1r")

      assert_prism_eval("\"foo\" in \"foo\"")
      assert_prism_eval("\"foo \#{1}\" in \"foo \#{1}\"")

      assert_prism_eval("false in false")
      assert_prism_eval("nil in nil")
      assert_prism_eval("self in self")
      assert_prism_eval("true in true")

      assert_prism_eval("5 in 0..10")
      assert_prism_eval("5 in 0...10")

      assert_prism_eval("[\"5\"] in %w[5]")

      assert_prism_eval("Prism in Prism")
      assert_prism_eval("Prism in ::Prism")

      assert_prism_eval(":prism in :prism")
      assert_prism_eval("%s[prism\#{1}] in %s[prism\#{1}]")
      assert_prism_eval("\"foo\" in /.../")
      assert_prism_eval("\"foo1\" in /...\#{1}/")
      assert_prism_eval("4 in ->(v) { v.even? }")

      assert_prism_eval("5 in foo")

      assert_prism_eval("1 in 2")

      # Bug: https://bugs.ruby-lang.org/issues/20956
      assert_prism_eval("1 in [1 | [1]]")
    end

    def test_MatchRequiredNode
      assert_prism_eval("1 => 1")
      assert_prism_eval("1.0 => 1.0")
      assert_prism_eval("1i => 1i")
      assert_prism_eval("1r => 1r")

      assert_prism_eval("\"foo\" => \"foo\"")
      assert_prism_eval("\"foo \#{1}\" => \"foo \#{1}\"")

      assert_prism_eval("false => false")
      assert_prism_eval("nil => nil")
      assert_prism_eval("true => true")

      assert_prism_eval("5 => 0..10")
      assert_prism_eval("5 => 0...10")

      assert_prism_eval("[\"5\"] => %w[5]")

      assert_prism_eval(":prism => :prism")
      assert_prism_eval("%s[prism\#{1}] => %s[prism\#{1}]")
      assert_prism_eval("\"foo\" => /.../")
      assert_prism_eval("\"foo1\" => /...\#{1}/")
      assert_prism_eval("4 => ->(v) { v.even? }")

      assert_prism_eval("5 => foo")
    end

    def test_PinnedExpressionNode
      assert_prism_eval("4 in ^(4)")
    end

    def test_PinnedVariableNode
      assert_prism_eval("module Prism; @@prism = 1; 1 in ^@@prism; end")
      assert_prism_eval("module Prism; @prism = 1; 1 in ^@prism; end")
      assert_prism_eval("$prism = 1; 1 in ^$prism")
      assert_prism_eval("prism = 1; 1 in ^prism")
      assert_prism_eval("[1].each { 1 => ^it }")
    end

    ############################################################################
    #  Miscellaneous                                                           #
    ############################################################################

    def test_eval
      assert_prism_eval("eval('1 + 1')", raw: true)
      assert_prism_eval("a = 1; eval('a + 1')", raw: true)

      assert_prism_eval(<<~CODE, raw: true)
        def prism_eval_splat(**bar)
          eval("bar")
        end
        prism_eval_splat(bar: 10)
      CODE

      assert_prism_eval(<<~CODE, raw: true)
        def prism_eval_keywords(baz:)
          eval("baz")
        end
        prism_eval_keywords(baz: 10)
      CODE

      assert_prism_eval(<<~CODE, raw: true)
        [1].each do |a|
          [2].each do |b|
            c = 3
            eval("a + b + c")
          end
        end
      CODE

      assert_prism_eval(<<~CODE, raw: true)
        def prism_eval_binding(b)
          eval("bar", b)
        end

        bar = :ok
        prism_eval_binding(binding)
      CODE
    end

    def test_ScopeNode
      assert_separately(%w[], <<~'RUBY')
        def compare_eval(source)
          ruby_eval = RubyVM::InstructionSequence.compile("module A; " + source + "; end").eval
          prism_eval = RubyVM::InstructionSequence.compile_prism("module B; " + source + "; end").eval

          assert_equal ruby_eval, prism_eval
        end

        def assert_prism_eval(source)
          $VERBOSE, verbose_bak = nil, $VERBOSE

          begin
            compare_eval(source)

            # Test "popped" functionality
            compare_eval("#{source}; 1")
          ensure
            $VERBOSE = verbose_bak
          end
        end

        assert_prism_eval("a = 1; 1.times do; { a: }; end")
        assert_prism_eval("a = 1; def foo(a); a; end")
      RUBY
    end

    ############################################################################
    # Errors                                                                   #
    ############################################################################

    def test_MissingNode
      # TODO
    end

    ############################################################################
    #  Encoding                                                                #
    ############################################################################

    def test_encoding
      assert_prism_eval('"però"')
      assert_prism_eval(":però")
    end

    def test_parse_file
      assert_nothing_raised do
        RubyVM::InstructionSequence.compile_file_prism(__FILE__)
      end

      error = assert_raise Errno::ENOENT do
        RubyVM::InstructionSequence.compile_file_prism("idontexist.rb")
      end

      assert_equal "No such file or directory - idontexist.rb", error.message

      assert_raise TypeError do
        RubyVM::InstructionSequence.compile_file_prism(nil)
      end
    end

    private

    def compare_eval(source, raw:, location:)
      source = raw ? source : "class Prism::TestCompilePrism\n#{source}\nend"

      ruby_eval = RubyVM::InstructionSequence.compile_parsey(source).eval
      prism_eval = RubyVM::InstructionSequence.compile_prism(source).eval

      if ruby_eval.is_a? Proc
        assert_equal ruby_eval.class, prism_eval.class, "@#{location.path}:#{location.lineno}"
      else
        assert_equal ruby_eval, prism_eval, "@#{location.path}:#{location.lineno}"
      end
    end

    def assert_prism_eval(source, raw: false)
      location = caller_locations(1, 1).first
      $VERBOSE, verbose_bak = nil, $VERBOSE

      begin
        compare_eval(source, raw:, location:)

        # Test "popped" functionality
        compare_eval("#{source}; 1", raw:, location:)
      ensure
        $VERBOSE = verbose_bak
      end
    end
  end
end
