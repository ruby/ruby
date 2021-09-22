# -*- coding: us-ascii -*-
# frozen_string_literal: false
require 'test/unit'

class TestImmutable < Test::Unit::TestCase
  class Person
    extend Immutable

    def initialize(name, age)
      @name = name
      @age = age
    end

    attr :name
    attr :age

    def freeze
      return self if frozen?

      @name.freeze
      @age.freeze

      super
    end
  end

  def assert_frozen(object)
    assert_predicate object, :frozen?
  end

  def test_new
    person = Person.new("Ash", 20)
    assert_frozen person
  end

  def test_frozen_attributes
    person = Person.new("Ash", 20)
    assert_frozen person.name
    assert_frozen person.age
  end

  def test_dup
    person = Person.new("Ash", 20)
    assert_frozen person.dup
  end

  def test_clone
    person = Person.new("Ash", 20)
    assert_frozen person.clone
  end

  def test_class_ancestors
    assert_include Person.singleton_class.ancestors, Immutable
  end
end
