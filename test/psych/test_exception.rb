require 'psych/helper'

module Psych
  class TestException < TestCase
    class Wups < Exception
      attr_reader :foo, :bar
      def initialize *args
        super
        @foo = 1
        @bar = 2
      end
    end

    def setup
      super
      @wups = Wups.new
    end

    def test_convert
      w = Psych.load(Psych.dump(@wups))
      assert_equal @wups, w
      assert_equal 1, w.foo
      assert_equal 2, w.bar
    end

    def test_to_yaml_properties
      class << @wups
        def to_yaml_properties
          [:@foo]
        end
      end

      w = Psych.load(Psych.dump(@wups))
      assert_equal @wups, w
      assert_equal 1, w.foo
      assert_nil w.bar
    end
  end
end
