require 'psych/helper'

module Psych
  class TestHash < TestCase
    def setup
      super
      @hash = { :a => 'b' }
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
