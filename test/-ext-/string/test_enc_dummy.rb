# frozen_string_literal: false
require 'test/unit'

class Test_StringEncDummy < Test::Unit::TestCase
  # assert_ractor starts a Ractor first, so the VM lock is really taken.

  def test_const_added_after_encoding_is_set_up
    assert_ractor("#{<<~"begin;"}\n#{<<~'end;'}", require: "-test-/string")
    begin;
      added = []
      Encoding.singleton_class.define_method(:const_added) do |name|
        added << [name, const_get(name).dummy?]
        super(name)
      end
      Bug::String.rb_define_dummy_encoding("TEST_ENC_DUMMY")
      assert_equal([[:TEST_ENC_DUMMY, true]], added)
    end;
  end
end
