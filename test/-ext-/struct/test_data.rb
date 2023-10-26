# frozen_string_literal: false
require 'test/unit'
require "-test-/struct"

class Bug::Struct::Test_Data < Test::Unit::TestCase
  def test_data_new_default
    klass = Bug::Struct.data_new(false)
    assert_equal Data, klass.superclass
    assert_equal %i[mem1 mem2], klass.members
  end

  def test_data_new_superclass
    superclass = Data.define
    klass = Bug::Struct.data_new(superclass)
    assert_equal superclass, klass.superclass
    assert_equal %i[mem1 mem2], klass.members
  end
end
