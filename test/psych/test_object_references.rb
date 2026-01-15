# frozen_string_literal: true
require_relative 'helper'

module Psych
  class TestObjectReferences < TestCase
    def test_range_has_references
      assert_reference_trip 1..2
    end

    def test_module_has_references
      assert_reference_trip Psych
    end

    def test_class_has_references
      assert_reference_trip TestObjectReferences
    end

    def test_rational_has_references
      assert_reference_trip Rational('1.2')
    end

    def test_complex_has_references
      assert_reference_trip Complex(1, 2)
    end

    def test_datetime_has_references
      assert_reference_trip DateTime.now
    end

    def test_struct_has_references
      assert_reference_trip Struct.new(:foo).new(1)
    end

    def test_data_has_references
      omit "Data requires ruby >= 3.2" if RUBY_VERSION < "3.2"
      assert_reference_trip Data.define(:foo).new(1)
    end

    def assert_reference_trip obj
      yml = Psych.dump([obj, obj])
      assert_match(/\*-?\d+/, yml)
      begin
        data = Psych.load yml
      rescue Psych::DisallowedClass
        data = Psych.unsafe_load yml
      end
      assert_same data.first, data.last
    end

    def test_float_references
      data = Psych.unsafe_load <<-eoyml
---\s
- &name 1.2
- *name
      eoyml
      assert_equal data.first, data.last
      assert_same data.first, data.last
    end

    def test_binary_references
      data = Psych.unsafe_load <<-eoyml
---
- &name !binary |-
  aGVsbG8gd29ybGQh
- *name
      eoyml
      assert_equal data.first, data.last
      assert_same data.first, data.last
    end

    def test_regexp_references
      data = Psych.unsafe_load <<-eoyml
---\s
- &name !ruby/regexp /pattern/i
- *name
      eoyml
      assert_equal data.first, data.last
      assert_same data.first, data.last
    end
  end
end
