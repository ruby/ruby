# frozen_string_literal: false
require 'test/unit'
require 'weakref'
require '-test-/gc/register'

class Test_GCRegisterAddress < Test::Unit::TestCase
  # Regression test for a heap-use-after-free in rb_gc_unregister_address():
  # unregistering one registered address must not corrupt the sibling slots or
  # leave a dangling pointer for the next GC to mark.
  def test_unregister_address_keeps_other_registered_addresses
    assert_equal(true, Bug::GC.unregister_address_keeps_siblings?)
  end

  def test_registered_value_survives_full_gc
    Bug::GC.register_static("registered on main".dup)

    2.times { GC.start(full_mark: true) }
    assert_equal("registered on main", Bug::GC.static_slot_value)
  ensure
    Bug::GC.unregister_static
  end

  def test_register_address_from_non_main_ractor_raises
    r = Ractor.new { Bug::GC.register_static("registered in child".dup) }
    e = assert_raise(Ractor::RemoteError) { r.value }
    assert_instance_of(Ractor::UnsafeError, e.cause)
  end

  def make_registered_weakref(level = 10)
    if level > 0
      make_registered_weakref(level - 1)
    else
      Bug::GC.register_static(v = "main owns this".dup)
      WeakRef.new(v)
    end
  end

  def test_unregister_address_from_non_main_ractor_raises
    Bug::GC.register_static("main owns this".dup)

    r = Ractor.new { Bug::GC.unregister_static }
    e = assert_raise(Ractor::RemoteError) { r.value }
    assert_instance_of(Ractor::UnsafeError, e.cause)
  ensure
    Bug::GC.unregister_static
  end

  def test_unregistered_value_is_collectable
    ref = make_registered_weakref
    assert_predicate(ref, :weakref_alive?)

    Bug::GC.unregister_static

    10.times do
      GC.start(full_mark: true)
      break unless ref.weakref_alive?
    end
    refute_predicate(ref, :weakref_alive?)
  ensure
    Bug::GC.unregister_static
  end

  def test_registered_value_survives_fork
    omit "fork not supported" unless Process.respond_to?(:fork)
    Bug::GC.register_static("pre-fork".dup)

    pid = fork do
      GC.start(full_mark: true)
      exit!(Bug::GC.static_slot_value == "pre-fork" ? 0 : 1)
    end
    _, status = Process.wait2(pid)
    assert_predicate(status, :success?)
  ensure
    Bug::GC.unregister_static
  end
end
