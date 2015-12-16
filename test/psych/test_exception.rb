# frozen_string_literal: false
require_relative 'helper'

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

    def test_naming_exception
      err     = String.xxx rescue $!
      new_err = Psych.load(Psych.dump(err))
      assert_equal err.message, new_err.message
    end

    def test_load_takes_file
      ex = assert_raises(Psych::SyntaxError) do
        Psych.load '--- `'
      end
      assert_nil ex.file

      ex = assert_raises(Psych::SyntaxError) do
        Psych.load '--- `', 'meow'
      end
      assert_equal 'meow', ex.file
    end

    def test_psych_parse_stream_takes_file
      ex = assert_raises(Psych::SyntaxError) do
        Psych.parse_stream '--- `'
      end
      assert_nil ex.file
      assert_match '(<unknown>)', ex.message

      ex = assert_raises(Psych::SyntaxError) do
        Psych.parse_stream '--- `', 'omg!'
      end
      assert_equal 'omg!', ex.file
      assert_match 'omg!', ex.message
    end

    def test_load_stream_takes_file
      ex = assert_raises(Psych::SyntaxError) do
        Psych.load_stream '--- `'
      end
      assert_nil ex.file
      assert_match '(<unknown>)', ex.message

      ex = assert_raises(Psych::SyntaxError) do
        Psych.load_stream '--- `', 'omg!'
      end
      assert_equal 'omg!', ex.file
    end

    def test_parse_file_exception
      Tempfile.create(['parsefile', 'yml']) {|t|
        t.binmode
        t.write '--- `'
        t.close
        ex = assert_raises(Psych::SyntaxError) do
          Psych.parse_file t.path
        end
        assert_equal t.path, ex.file
      }
    end

    def test_load_file_exception
      Tempfile.create(['loadfile', 'yml']) {|t|
        t.binmode
        t.write '--- `'
        t.close
        ex = assert_raises(Psych::SyntaxError) do
          Psych.load_file t.path
        end
        assert_equal t.path, ex.file
      }
    end

    def test_psych_parse_takes_file
      ex = assert_raises(Psych::SyntaxError) do
        Psych.parse '--- `'
      end
      assert_match '(<unknown>)', ex.message
      assert_nil ex.file

      ex = assert_raises(Psych::SyntaxError) do
        Psych.parse '--- `', 'omg!'
      end
      assert_match 'omg!', ex.message
    end

    def test_attributes
      e = assert_raises(Psych::SyntaxError) {
        Psych.load '--- `foo'
      }

      assert_nil e.file
      assert_equal 1, e.line
      assert_equal 5, e.column
      # FIXME: offset isn't being set correctly by libyaml
      # assert_equal 5, e.offset

      assert e.problem
      assert e.context
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

    def test_psych_syntax_error
      Tempfile.create(['parsefile', 'yml']) do |t|
        t.binmode
        t.write '--- `'
        t.close

        begin
          Psych.parse_file t.path
        rescue StandardError
          assert true # count assertion
        ensure
          return unless $!

          ancestors = $!.class.ancestors.inspect

          flunk "Psych::SyntaxError not rescued by StandardError: #{ancestors}"
        end
      end
    end

  end
end
