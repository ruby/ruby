require_relative 'helper'

module Psych
  class TestDeprecated < TestCase
    class QuickEmitter
      attr_reader :name
      attr_reader :value

      def initialize
        @name  = 'hello!!'
        @value = 'Friday!'
      end

      def to_yaml opts = {}
        Psych.quick_emit object_id, opts do |out|
          out.map taguri, to_yaml_style do |map|
            map.add 'name', @name
            map.add 'value', nil
          end
        end
      end
    end

    def setup
      @qe = QuickEmitter.new
    end

    def test_quick_emit
      qe2 = Psych.load @qe.to_yaml
      assert_equal @qe.name, qe2.name
      assert_instance_of QuickEmitter, qe2
      assert_nil qe2.value
    end

    def test_recursive_quick_emit
      hash  = { :qe => @qe }
      hash2 = Psych.load Psych.dump hash
      qe    = hash2[:qe]

      assert_equal @qe.name, qe.name
      assert_instance_of QuickEmitter, qe
      assert_nil qe.value
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
      hash2 = Psych.load Psych.dump hash
      qe    = hash2[:qe]

      assert_equal qeew.name, qe.name
      assert_instance_of QuickEmitterEncodeWith, qe
      assert_nil qe.value
    end

    class YamlInit
      attr_reader :name
      attr_reader :value

      def initialize
        @name  = 'hello!!'
        @value = 'Friday!'
      end

      def yaml_initialize tag, vals
        vals.each { |ivar, val| instance_variable_set "@#{ivar}", 'TGIF!' }
      end
    end

    def test_yaml_initialize
      hash  = { :yi => YamlInit.new }
      hash2 = Psych.load Psych.dump hash
      yi    = hash2[:yi]

      assert_equal 'TGIF!', yi.name
      assert_equal 'TGIF!', yi.value
      assert_instance_of YamlInit, yi
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
      hash2 = Psych.load Psych.dump hash
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

    class YamlAs
      yaml_as 'helloworld'
    end

    def test_yaml_as
      assert_match(/helloworld/, Psych.dump(YamlAs.new))
    end
  end
end
