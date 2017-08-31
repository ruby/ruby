# frozen_string_literal: true
require_relative 'helper'

module Psych
  class TestHash < TestCase
    class X < Hash
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

    def test_referenced_hash_with_ivar
      a = [1,2,3,4,5]
      t1 = [HashWithCustomInit.new(a)]
      t1 << t1.first
      assert_cycle t1
    end

    def test_custom_initialized
      a = [1,2,3,4,5]
      t1 = HashWithCustomInit.new(a)
      t2 = Psych.load(Psych.dump(t1))
      assert_equal t1, t2
      assert_cycle t1
    end

    def test_custom_initialize_no_ivar
      t1 = HashWithCustomInitNoIvar.new(nil)
      t2 = Psych.load(Psych.dump(t1))
      assert_equal t1, t2
      assert_cycle t1
    end

    def test_hash_subclass_with_ivars
      x = X.new
      x[:a] = 'b'
      x.instance_variable_set :@foo, 'bar'
      dup = Psych.load Psych.dump x
      assert_cycle x
      assert_equal 'bar', dup.instance_variable_get(:@foo)
      assert_equal X, dup.class
    end

    def test_load_with_class_syck_compatibility
      hash = Psych.load "--- !ruby/object:Hash\n:user_id: 7\n:username: Lucas\n"
      assert_equal({ user_id: 7, username: 'Lucas'}, hash)
    end

    def test_empty_subclass
      assert_match "!ruby/hash:#{X}", Psych.dump(X.new)
      x = Psych.load Psych.dump X.new
      assert_equal X, x.class
    end

    def test_map
      x = Psych.load "--- !map:#{X} { }\n"
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
      hash = Psych.load(<<-eoyml)
---
foo: &foo
  hello: world
bar:
  <<: *foo
eoyml
      assert_equal({"foo"=>{"hello"=>"world"}, "bar"=>{"hello"=>"world"}}, hash)
    end
  end
end
