require_relative 'helper'

module Psych
  class TestHash < TestCase
    class X < Hash
    end

    def setup
      super
      @hash = { :a => 'b' }
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
