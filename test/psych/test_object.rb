require 'psych/helper'

module Psych
  class Tagged
    yaml_tag '!foo'

    attr_accessor :baz

    def initialize
      @baz = 'bar'
    end
  end

  class TestObject < TestCase
    def test_dump_with_tag
      tag = Tagged.new
      assert_match('foo', Psych.dump(tag))
    end

    def test_tag_round_trip
      tag   = Tagged.new
      tag2  = Psych.load(Psych.dump(tag))
      assert_equal tag.baz, tag2.baz
      assert_instance_of(Tagged, tag2)
    end
  end
end
