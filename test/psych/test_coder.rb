# frozen_string_literal: true
require_relative 'helper'

module Psych
  class TestCoder < TestCase
    class InitApi
      attr_accessor :implicit
      attr_accessor :style
      attr_accessor :tag
      attr_accessor :a, :b, :c

      def initialize
        @a = 1
        @b = 2
        @c = 3
      end

      def init_with coder
        @a = coder['aa']
        @b = coder['bb']
        @implicit = coder.implicit
        @tag      = coder.tag
        @style    = coder.style
      end

      def encode_with coder
        coder['aa'] = @a
        coder['bb'] = @b
      end
    end

    class TaggingCoder < InitApi
      def encode_with coder
        super
        coder.tag       = coder.tag.sub(/!/, '!hello')
        coder.implicit  = false
        coder.style     = Psych::Nodes::Mapping::FLOW
      end
    end

    class ScalarCoder
      def encode_with coder
        coder.scalar = "foo"
      end
    end

    class Represent
      yaml_tag 'foo'
      def encode_with coder
        coder.represent_scalar 'foo', 'bar'
      end
    end

    class RepresentWithInit
      yaml_tag name
      attr_accessor :str

      def init_with coder
        @str = coder.scalar
      end

      def encode_with coder
        coder.represent_scalar self.class.name, 'bar'
      end
    end

    class RepresentWithSeq
      yaml_tag name
      attr_accessor :seq

      def init_with coder
        @seq = coder.seq
      end

      def encode_with coder
        coder.represent_seq self.class.name, %w{ foo bar }
      end
    end

    class RepresentWithMap
      yaml_tag name
      attr_accessor :map

      def init_with coder
        @map = coder.map
      end

      def encode_with coder
        coder.represent_map self.class.name, { "string" => 'a', :symbol => 'b' }
      end
    end

    class RepresentWithObject
      def encode_with coder
        coder.represent_object self.class.name, 20
      end
    end

    class Referential
      attr_reader :a

      def initialize
        @a = self
      end

      def encode_with(c)
        c['a'] = @a
      end

      def init_with(c)
        @a = c['a']
      end
    end

    class CustomEncode
      def initialize(**opts)
        @opts = opts
      end

      def encode_with(coder)
        @opts.each { |k,v| coder.public_send :"#{k}=", v }
      end
    end

    def test_self_referential
      x = Referential.new
      copy = Psych.unsafe_load Psych.dump x
      assert_equal copy, copy.a
    end

    def test_represent_with_object
      thing = Psych.load(Psych.dump(RepresentWithObject.new))
      assert_equal 20, thing
    end

    def test_json_dump_exclude_tag
      refute_match('TestCoder::InitApi', Psych.to_json(InitApi.new))
    end

    def test_map_takes_block
      coder = Psych::Coder.new 'foo'
      tag = coder.tag
      style = coder.style
      coder.map { |map| map.add 'foo', 'bar' }
      assert_equal 'bar', coder['foo']
      assert_equal tag, coder.tag
      assert_equal style, coder.style
    end

    def test_map_with_tag
      coder = Psych::Coder.new 'foo'
      coder.map('hello') { |map| map.add 'foo', 'bar' }
      assert_equal 'bar', coder['foo']
      assert_equal 'hello', coder.tag
    end

    def test_map_with_tag_and_style
      coder = Psych::Coder.new 'foo'
      coder.map('hello', 'world') { |map| map.add 'foo', 'bar' }
      assert_equal 'bar', coder['foo']
      assert_equal 'hello', coder.tag
      assert_equal 'world', coder.style
    end

    def test_represent_map
      thing = Psych.unsafe_load(Psych.dump(RepresentWithMap.new))
      assert_equal({ "string" => 'a', :symbol => 'b' }, thing.map)
    end

    def test_represent_sequence
      thing = Psych.unsafe_load(Psych.dump(RepresentWithSeq.new))
      assert_equal %w{ foo bar }, thing.seq
    end

    def test_represent_with_init
      thing = Psych.unsafe_load(Psych.dump(RepresentWithInit.new))
      assert_equal 'bar', thing.str
    end

    def test_represent!
      assert_match(/foo/, Psych.dump(Represent.new))
      assert_instance_of(Represent, Psych.unsafe_load(Psych.dump(Represent.new)))
    end

    def test_scalar_coder
      foo = Psych.load(Psych.dump(ScalarCoder.new))
      assert_equal 'foo', foo
    end

    def test_load_dumped_tagging
      foo = InitApi.new
      bar = Psych.unsafe_load(Psych.dump(foo))
      assert_equal false, bar.implicit
      assert_equal "!ruby/object:Psych::TestCoder::InitApi", bar.tag
      assert_equal Psych::Nodes::Mapping::BLOCK, bar.style
    end

    def test_dump_with_tag
      foo = TaggingCoder.new
      assert_match(/hello/, Psych.dump(foo))
      assert_match(/\{aa/, Psych.dump(foo))
    end

    def test_dump_encode_with
      foo = InitApi.new
      assert_match(/aa/, Psych.dump(foo))
    end

    def test_dump_init_with
      foo = InitApi.new
      bar = Psych.unsafe_load(Psych.dump(foo))
      assert_equal foo.a, bar.a
      assert_equal foo.b, bar.b
      assert_nil bar.c
    end

    def test_coder_style_map_default
      foo = Psych.dump a: 1, b: 2
      assert_equal "---\n:a: 1\n:b: 2\n", foo
    end

    def test_coder_style_map_any
      foo = Psych.dump CustomEncode.new \
        map: {a: 1, b: 2},
        style: Psych::Nodes::Mapping::ANY,
        tag: nil
      assert_equal "---\n:a: 1\n:b: 2\n", foo
    end

    def test_coder_style_map_block
      foo = Psych.dump CustomEncode.new \
        map: {a: 1, b: 2},
        style: Psych::Nodes::Mapping::BLOCK,
        tag: nil
      assert_equal "---\n:a: 1\n:b: 2\n", foo
    end

    def test_coder_style_map_flow
      foo = Psych.dump CustomEncode.new \
        map: { a: 1, b: 2 },
        style: Psych::Nodes::Mapping::FLOW,
        tag: nil
      assert_equal "--- {! ':a': 1, ! ':b': 2}\n", foo
    end

    def test_coder_style_seq_default
      foo = Psych.dump [ 1, 2, 3 ]
      assert_equal "---\n- 1\n- 2\n- 3\n", foo
    end

    def test_coder_style_seq_any
      foo = Psych.dump CustomEncode.new \
        seq: [ 1, 2, 3 ],
        style: Psych::Nodes::Sequence::ANY,
        tag: nil
      assert_equal "---\n- 1\n- 2\n- 3\n", foo
    end

    def test_coder_style_seq_block
      foo = Psych.dump CustomEncode.new \
        seq: [ 1, 2, 3 ],
        style: Psych::Nodes::Sequence::BLOCK,
        tag: nil
      assert_equal "---\n- 1\n- 2\n- 3\n", foo
    end

    def test_coder_style_seq_flow
      foo = Psych.dump CustomEncode.new \
        seq: [ 1, 2, 3 ],
        style: Psych::Nodes::Sequence::FLOW,
        tag: nil
      assert_equal "--- [1, 2, 3]\n", foo
    end

    def test_coder_style_scalar_default
      foo = Psych.dump 'some scalar'
      assert_match(/\A--- some scalar\n(?:\.\.\.\n)?\z/, foo)
    end

    def test_coder_style_scalar_any
      foo = Psych.dump CustomEncode.new \
        scalar: 'some scalar',
        style: Psych::Nodes::Scalar::ANY,
        tag: nil
      assert_match(/\A--- some scalar\n(?:\.\.\.\n)?\z/, foo)
    end

    def test_coder_style_scalar_plain
      foo = Psych.dump CustomEncode.new \
        scalar: 'some scalar',
        style: Psych::Nodes::Scalar::PLAIN,
        tag: nil
      assert_match(/\A--- some scalar\n(?:\.\.\.\n)?\z/, foo)
    end

    def test_coder_style_scalar_single_quoted
      foo = Psych.dump CustomEncode.new \
        scalar: 'some scalar',
        style: Psych::Nodes::Scalar::SINGLE_QUOTED,
        tag: nil
      assert_equal "--- ! 'some scalar'\n", foo
    end

    def test_coder_style_scalar_double_quoted
      foo = Psych.dump CustomEncode.new \
        scalar: 'some scalar',
        style: Psych::Nodes::Scalar::DOUBLE_QUOTED,
        tag: nil
      assert_equal %Q'--- ! "some scalar"\n', foo
    end

    def test_coder_style_scalar_literal
      foo = Psych.dump CustomEncode.new \
        scalar: 'some scalar',
        style: Psych::Nodes::Scalar::LITERAL,
        tag: nil
      assert_equal "--- ! |-\n  some scalar\n", foo
    end

    def test_coder_style_scalar_folded
      foo = Psych.dump CustomEncode.new \
        scalar: 'some scalar',
        style: Psych::Nodes::Scalar::FOLDED,
        tag: nil
      assert_equal "--- ! >-\n  some scalar\n", foo
    end
  end
end
