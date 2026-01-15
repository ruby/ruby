# frozen_string_literal: true
require_relative 'helper'

class PsychDataWithIvar < Data.define(:foo)
  attr_reader :bar
  def initialize(**)
    @bar = 'hello'
    super
  end
end unless RUBY_VERSION < "3.2"

module Psych
  class TestData < TestCase
    class SelfReferentialData < Data.define(:foo)
      attr_accessor :ref
      def initialize(foo:)
        @ref = self
        super
      end
    end unless RUBY_VERSION < "3.2"

    def setup
      omit "Data requires ruby >= 3.2" if RUBY_VERSION < "3.2"
    end

    # TODO: move to another test?
    def test_dump_data
      assert_equal <<~eoyml, Psych.dump(PsychDataWithIvar["bar"])
        --- !ruby/data-with-ivars:PsychDataWithIvar
        members:
          foo: bar
        ivars:
          "@bar": hello
      eoyml
    end

    def test_self_referential_data
      circular = SelfReferentialData.new("foo")

      loaded = Psych.unsafe_load(Psych.dump(circular))
      assert_instance_of(SelfReferentialData, loaded.ref)

      assert_equal(circular, loaded)
      assert_same(loaded, loaded.ref)
    end

    def test_roundtrip
      thing = PsychDataWithIvar.new("bar")
      data = Psych.unsafe_load(Psych.dump(thing))

      assert_equal "hello", data.bar
      assert_equal "bar",   data.foo
    end

    def test_load
      obj = Psych.unsafe_load(<<~eoyml)
        --- !ruby/data-with-ivars:PsychDataWithIvar
        members:
          foo: bar
        ivars:
          "@bar": hello
      eoyml

      assert_equal "hello", obj.bar
      assert_equal "bar",   obj.foo
    end

    def test_members_must_be_identical
      TestData.const_set :D, Data.define(:a, :b)
      d = Psych.dump(TestData::D.new(1, 2))

      # more members
      TestData.send :remove_const, :D
      TestData.const_set :D, Data.define(:a, :b, :c)
      e = assert_raise(ArgumentError) { Psych.unsafe_load d }
      assert_equal 'missing keyword: :c', e.message

      # less members
      TestData.send :remove_const, :D
      TestData.const_set :D, Data.define(:a)
      e = assert_raise(ArgumentError) { Psych.unsafe_load d }
      assert_equal 'unknown keyword: :b', e.message

      # completely different members
      TestData.send :remove_const, :D
      TestData.const_set :D, Data.define(:foo, :bar)
      e = assert_raise(ArgumentError) { Psych.unsafe_load d }
      assert_equal 'unknown keywords: :a, :b', e.message
    ensure
      TestData.send :remove_const, :D
    end
  end
end

