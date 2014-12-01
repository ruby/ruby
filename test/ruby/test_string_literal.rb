# -*- immutable: string -*-

require 'test/unit'
require_relative 'test_string_literal_mutable.rb'


STRINGS = [
  'hello',
  "hello",
  %{Hello},
  %Q{Hello},
  %q{Hello},
  <<-EOS
    Hello World
  EOS
]

class TestStringLiteral < Test::Unit::TestCase
  def mutate(str)
    str.slice!(1, 2)
  end

  def interpolated_string(message)
    "Interpolated: #{message}"
  end

  def some_string
    "A nice frozen string!"
  end

  def test_strings_are_immutable_in_this_file
    STRINGS.each do |s|
      exception = assert_raise RuntimeError, s do
        mutate(s)
      end
      assert_match /can't modify frozen String/, exception.message
    end
  end

  def test_strings_in_other_file_are_mutable
    mutate(TestStringLiteralMutable::CONSTANT)
    assert_equal "SING", TestStringLiteralMutable::CONSTANT
  end

  def test_literal_strings_should_have_the_same_object_id
    s1 = some_string
    s2 = some_string
    assert_equal s1.object_id, s2.object_id
  end

  def test_different_literal_strings_with_the_same_value_in_the_same_file_should_have_the_same_object_id
    s1 = some_string
    s2 = "A nice frozen string!"
    assert_equal s2.object_id, s2.object_id
  end

  def test_string_interpolation
    str = interpolated_string("blah blah")
    exception = assert_raise RuntimeError do
      mutate(str)
    end
    assert_match /can't modify frozen String/, exception.message
  end

  def test_interpolated_strings_should_have_a_different_object_id
    s1 = interpolated_string('x')
    s2 = interpolated_string('x')
    assert_equal "Interpolated: x", s1
    assert_equal "Interpolated: x", s2
    assert_not_equal s1.object_id, s2.object_id
  end
end
