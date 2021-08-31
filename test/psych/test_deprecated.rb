# frozen_string_literal: true
require_relative 'helper'

module Psych
  class TestDeprecated < TestCase
    def teardown
      $VERBOSE = @orig_verbose
      Psych.domain_types.clear
    end

    class QuickEmitter; end

    def setup
      @orig_verbose, $VERBOSE = $VERBOSE, false
    end

    class QuickEmitterEncodeWith
      attr_reader :name
      attr_reader :value

      def initialize
        @name  = 'hello!!'
        @value = 'Friday!'
      end

      def encode_with coder
        coder.map do |map|
          map.add 'name', @name
          map.add 'value', nil
        end
      end

      def to_yaml opts = {}
        raise
      end
    end

    ###
    # An object that defines both to_yaml and encode_with should only call
    # encode_with.
    def test_recursive_quick_emit_encode_with
      qeew = QuickEmitterEncodeWith.new
      hash  = { :qe => qeew }
      hash2 = Psych.unsafe_load Psych.dump hash
      qe    = hash2[:qe]

      assert_equal qeew.name, qe.name
      assert_instance_of QuickEmitterEncodeWith, qe
      assert_nil qe.value
    end

    class YamlInitAndInitWith
      attr_reader :name
      attr_reader :value

      def initialize
        @name  = 'shaners'
        @value = 'Friday!'
      end

      def init_with coder
        coder.map.each { |ivar, val| instance_variable_set "@#{ivar}", 'TGIF!' }
      end

      def yaml_initialize tag, vals
        raise
      end
    end

    ###
    # An object that implements both yaml_initialize and init_with should not
    # receive the yaml_initialize call.
    def test_yaml_initialize_and_init_with
      hash  = { :yi => YamlInitAndInitWith.new }
      hash2 = Psych.unsafe_load Psych.dump hash
      yi    = hash2[:yi]

      assert_equal 'TGIF!', yi.name
      assert_equal 'TGIF!', yi.value
      assert_instance_of YamlInitAndInitWith, yi
    end

    def test_coder_scalar
      coder = Psych::Coder.new 'foo'
      coder.scalar('tag', 'some string', :plain)
      assert_equal 'tag', coder.tag
      assert_equal 'some string', coder.scalar
      assert_equal :scalar, coder.type
    end
  end
end
