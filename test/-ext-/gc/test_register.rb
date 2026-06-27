# frozen_string_literal: false
require 'test/unit'
require '-test-/gc/register'

class Test_GCRegisterAddress < Test::Unit::TestCase
  # Regression test for a heap-use-after-free in rb_gc_unregister_address():
  # unregistering one registered address must not corrupt the sibling slots or
  # leave a dangling pointer for the next GC to mark.
  def test_unregister_address_keeps_other_registered_addresses
    assert_equal(true, Bug::GC.unregister_address_keeps_siblings?)
  end
end
