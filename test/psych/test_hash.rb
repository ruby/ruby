# frozen_string_literal: true
require_relative 'helper'

module Psych
  class TestHash < TestCase
    class X < Hash
    end

    class HashWithIvar < Hash
      def initialize
        @keys = []
        super
      end

      def []=(k, v)
        @keys << k
        super(k, v)
      end
    end

    class HashWithCustomInit < Hash
      attr_reader :obj
      def initialize(obj)
        @obj = obj
      end
    end

    class HashWithCustomInitNoIvar < Hash
      def initialize(obj)
        # *shrug*
      end
    end

    def setup
      super
      @hash = { :a => 'b' }
    end

    def test_hash_with_ivar
      t1 = HashWithIvar.new
      t1[:foo] = :bar
      t2 = Psych.unsafe_load(Psych.dump(t1))
      assert_equal t1, t2
      assert_cycle t1
    end

    def test_referenced_hash_with_ivar
      a = [1,2,3,4,5]
      t1 = [HashWithCustomInit.new(a)]
      t1 << t1.first
      assert_cycle t1
    end

    def test_custom_initialized
      a = [1,2,3,4,5]
      t1 = HashWithCustomInit.new(a)
      t2 = Psych.unsafe_load(Psych.dump(t1))
      assert_equal t1, t2
      assert_cycle t1
    end

    def test_custom_initialize_no_ivar
      t1 = HashWithCustomInitNoIvar.new(nil)
      t2 = Psych.unsafe_load(Psych.dump(t1))
      assert_equal t1, t2
      assert_cycle t1
    end

    def test_hash_subclass_with_ivars
      x = X.new
      x[:a] = 'b'
      x.instance_variable_set :@foo, 'bar'
      dup = Psych.unsafe_load Psych.dump x
      assert_cycle x
      assert_equal 'bar', dup.instance_variable_get(:@foo)
      assert_equal X, dup.class
    end

    def test_load_with_class_syck_compatibility
      hash = Psych.unsafe_load "--- !ruby/object:Hash\n:user_id: 7\n:username: Lucas\n"
      assert_equal({ user_id: 7, username: 'Lucas'}, hash)
    end

    def test_empty_subclass
      assert_match "!ruby/hash:#{X}", Psych.dump(X.new)
      x = Psych.unsafe_load Psych.dump X.new
      assert_equal X, x.class
    end

    def test_map
      x = Psych.unsafe_load "--- !map:#{X} { }\n"
      assert_equal X, x.class
    end

    def test_self_referential
      @hash['self'] = @hash
      assert_cycle(@hash)
    end

    def test_cycles
      assert_cycle(@hash)
    end

    def test_ref_append
      hash = Psych.unsafe_load(<<~eoyml)
        ---
        foo: &foo
          hello: world
        bar:
          <<: *foo
      eoyml
      assert_equal({"foo"=>{"hello"=>"world"}, "bar"=>{"hello"=>"world"}}, hash)
    end

    def test_anchor_reuse
      hash = Psych.unsafe_load(<<~eoyml)
        ---
        foo: &foo
          hello: world
        bar: *foo
      eoyml
      assert_equal({"foo"=>{"hello"=>"world"}, "bar"=>{"hello"=>"world"}}, hash)
      assert_same(hash.fetch("foo"), hash.fetch("bar"))
    end

    def test_raises_if_anchor_not_defined
      assert_raise(Psych::AnchorNotDefined) do
        Psych.unsafe_load(<<~eoyml)
          ---
          foo: &foo
            hello: world
          bar: *not_foo
        eoyml
      end
    end

    def test_recursive_hash
      h = { }
      h["recursive_reference"] = h

      loaded = Psych.load(Psych.dump(h), aliases: true)

      assert_same loaded, loaded.fetch("recursive_reference")
    end

    def test_recursive_hash_uses_alias
      h = { }
      h["recursive_reference"] = h

      assert_raise(AliasesNotEnabled) do
        Psych.load(Psych.dump(h), aliases: false)
      end
    end

    def test_key_deduplication
      unless String.method_defined?(:-@) && (-("a" * 20)).equal?((-("a" * 20)))
        pend "This Ruby implementation doesn't support string deduplication"
      end

      hashes = Psych.load(<<~eoyml)
        ---
        - unique_identifier: 1
        - unique_identifier: 2
      eoyml

      assert_same hashes[0].keys.first, hashes[1].keys.first
    end
  end
end
