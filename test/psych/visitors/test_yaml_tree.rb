# frozen_string_literal: true
require 'psych/helper'
require 'delegate'

module Psych
  module Visitors
    class TestYAMLTree < TestCase
      class TestDelegatorClass < Delegator
        def initialize(obj); super; @obj = obj; end
        def __setobj__(obj); @obj = obj; end
        def __getobj__; @obj if defined?(@obj); end
      end

      class TestSimpleDelegatorClass < SimpleDelegator
      end

      def setup
        super
        @v = Visitors::YAMLTree.create
      end

      def test_tree_can_be_called_twice
        @v.start
        @v << Object.new
        t = @v.tree
        assert_equal t, @v.tree
      end

      def test_yaml_tree_can_take_an_emitter
        io = StringIO.new
        e  = Psych::Emitter.new io
        v = Visitors::YAMLTree.create({}, e)
        v.start
        v << "hello world"
        v.finish

        assert_include io.string, "hello world"
      end

      def test_binary_formatting
        gif = "GIF89a\f\x00\f\x00\x84\x00\x00\xFF\xFF\xF7\xF5\xF5\xEE\xE9\xE9\xE5fff\x00\x00\x00\xE7\xE7\xE7^^^\xF3\xF3\xED\x8E\x8E\x8E\xE0\xE0\xE0\x9F\x9F\x9F\x93\x93\x93\xA7\xA7\xA7\x9E\x9E\x9Eiiiccc\xA3\xA3\xA3\x84\x84\x84\xFF\xFE\xF9\xFF\xFE\xF9\xFF\xFE\xF9\xFF\xFE\xF9\xFF\xFE\xF9\xFF\xFE\xF9\xFF\xFE\xF9\xFF\xFE\xF9\xFF\xFE\xF9\xFF\xFE\xF9\xFF\xFE\xF9\xFF\xFE\xF9\xFF\xFE\xF9\xFF\xFE\xF9!\xFE\x0EMade with GIMP\x00,\x00\x00\x00\x00\f\x00\f\x00\x00\x05,  \x8E\x810\x9E\xE3@\x14\xE8i\x10\xC4\xD1\x8A\b\x1C\xCF\x80M$z\xEF\xFF0\x85p\xB8\xB01f\r\e\xCE\x01\xC3\x01\x1E\x10' \x82\n\x01\x00;".b
        @v << gif
        scalar = @v.tree.children.first.children.first
        assert_equal Psych::Nodes::Scalar::LITERAL, scalar.style
      end

      def test_object_has_no_class
        yaml = Psych.dump(Object.new)
        assert(Psych.dump(Object.new) !~ /Object/, yaml)
      end

      def test_struct_const
        foo = Struct.new("Foo", :bar)
        assert_cycle foo.new('bar')
        Struct.instance_eval { remove_const(:Foo) }
      end

      A = Struct.new(:foo)

      def test_struct
        assert_cycle A.new('bar')
      end

      def test_struct_anon
        s = Struct.new(:foo).new('bar')
        obj =  Psych.unsafe_load(Psych.dump(s))
        assert_equal s.foo, obj.foo
      end

      def test_override_method
        s = Struct.new(:method).new('override')
        obj =  Psych.unsafe_load(Psych.dump(s))
        assert_equal s.method, obj.method
      end

      D = Data.define(:foo) unless RUBY_VERSION < "3.2"

      def test_data
        omit "Data requires ruby >= 3.2" if RUBY_VERSION < "3.2"
        assert_cycle D.new('bar')
      end

      def test_data_anon
        omit "Data requires ruby >= 3.2" if RUBY_VERSION < "3.2"
        d = Data.define(:foo).new('bar')
        obj =  Psych.unsafe_load(Psych.dump(d))
        assert_equal d.foo, obj.foo
      end

      def test_data_override_method
        omit "Data requires ruby >= 3.2" if RUBY_VERSION < "3.2"
        d = Data.define(:method).new('override')
        obj =  Psych.unsafe_load(Psych.dump(d))
        assert_equal d.method, obj.method
      end

      def test_exception
        ex = Exception.new 'foo'
        loaded = Psych.unsafe_load(Psych.dump(ex))

        assert_equal ex.message, loaded.message
        assert_equal ex.class, loaded.class
      end

      def test_regexp
        assert_cycle(/foo/)
        assert_cycle(/foo/i)
        assert_cycle(/foo/mx)
      end

      def test_time
        t = Time.now
        assert_equal t, Psych.unsafe_load(Psych.dump(t))
      end

      def test_date
        date = Date.strptime('2002-12-14', '%Y-%m-%d')
        assert_cycle date
      end

      def test_rational
        assert_cycle Rational(1,2)
      end

      def test_complex
        assert_cycle Complex(1,2)
      end

      def test_scalar
        assert_cycle 'foo'
        assert_cycle ':foo'
        assert_cycle ''
        assert_cycle ':'
      end

      def test_boolean
        assert_cycle true
        assert_cycle 'true'
        assert_cycle false
        assert_cycle 'false'
      end

      def test_range_inclusive
        assert_cycle 1..2
      end

      def test_range_exclusive
        assert_cycle 1...2
      end

      def test_anon_class
        assert_raise(TypeError) do
          @v.accept Class.new
        end

        assert_raise(TypeError) do
          Psych.dump(Class.new)
        end
      end

      def test_hash
        assert_cycle('a' => 'b')
      end

      def test_list
        assert_cycle(%w{ a b })
        assert_cycle([1, 2.2])
      end

      def test_symbol
        assert_cycle :foo
      end

      def test_int
        assert_cycle 1
        assert_cycle(-1)
        assert_cycle '1'
        assert_cycle '-1'
      end

      def test_float
        assert_cycle 1.2
        assert_cycle '1.2'

        assert Psych.load(Psych.dump(0.0 / 0.0)).nan?
        assert_equal 1, Psych.load(Psych.dump(1 / 0.0)).infinite?
        assert_equal(-1, Psych.load(Psych.dump(-1 / 0.0)).infinite?)
      end

      def test_string
        assert_include(Psych.dump({'a' => '017'}), "'017'")
        assert_include(Psych.dump({'a' => '019'}), "'019'")
        assert_include(Psych.dump({'a' => '01818'}), "'01818'")
      end

      # http://yaml.org/type/null.html
      def test_nil
        assert_cycle nil
        assert_nil Psych.load('null')
        assert_nil Psych.load('Null')
        assert_nil Psych.load('NULL')
        assert_nil Psych.load('~')
        assert_equal({'foo' => nil}, Psych.load('foo: '))

        assert_cycle 'null'
        assert_cycle 'nUll'
        assert_cycle '~'
      end

      def test_delegator
        assert_cycle(TestDelegatorClass.new([1, 2, 3]))
      end

      def test_simple_delegator
        assert_cycle(TestSimpleDelegatorClass.new([1, 2, 3]))
      end
    end
  end
end
