# frozen_string_literal: false
require 'test/unit'
require "-test-/struct"

class Bug::Struct::Test_DefineUnder < Test::Unit::TestCase
  def test_define_under
    klass = Bug::Struct.define_under("DefineUnder", "a")

    assert_same(klass, Bug::Struct::DefineUnder)
    assert_equal("Bug::Struct::DefineUnder", klass.name)
    assert_equal([:a], klass.members)
    assert_equal(1, klass.new(1).a)
  ensure
    Bug::Struct.send(:remove_const, :DefineUnder)
  end

  def test_define_under_calls_inherited_with_a_complete_class
    assert_separately(["-r-test-/struct"], <<~'RUBY')
      seen = []
      Struct.define_singleton_method(:inherited) do |klass|
        seen << [klass.name, klass.members, klass.new(1).a]
        super(klass)
      end

      Bug::Struct.define_under("Inherited", "a")

      assert_equal([["Bug::Struct::Inherited", [:a], 1]], seen)
    RUBY
  end
end
