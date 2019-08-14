# frozen_string_literal: true
require_relative 'helper'
require 'delegate'

module Psych
  class TestMarshalable < TestCase
    def test_objects_defining_marshal_dump_and_marshal_load_can_be_dumped
      sd = SimpleDelegator.new(1)
      loaded = Psych.load(Psych.dump(sd))

      assert_instance_of(SimpleDelegator, loaded)
      assert_equal(sd, loaded)
    end

    class PsychCustomMarshalable < BasicObject
      attr_reader :foo

      def initialize(foo)
        @foo = foo
      end

      def marshal_dump
        [foo]
      end

      def mashal_load(data)
        @foo = data[0]
      end

      def init_with(coder)
        @foo = coder['foo']
      end

      def encode_with(coder)
        coder['foo'] = 2
      end

      def respond_to?(method)
        [:marshal_dump, :marshal_load, :init_with, :encode_with].include?(method)
      end

      def class
        PsychCustomMarshalable
      end
    end

    def test_init_with_takes_priority_over_marshal_methods
      obj = PsychCustomMarshalable.new(1)
      loaded = Psych.load(Psych.dump(obj))

      assert(PsychCustomMarshalable === loaded)
      assert_equal(2, loaded.foo)
    end
  end
end
