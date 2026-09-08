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

  def test_registered_value_survives_owner_ractor_join
    r = Ractor.new { Bug::GC.register_static("registered in child".dup) }
    assert_equal(true, r.value)

    2.times { GC.start(full_mark: true) }
    assert_equal("registered in child", Bug::GC.static_slot_value)
  ensure
    Bug::GC.unregister_static
  end

  def make_registered_weakref(level = 10)
    if level > 0
      make_registered_weakref(level - 1)
    else
      Bug::GC.register_static(v = "main owns this".dup)
      WeakRef.new(v)
    end
  end

  def test_unregister_address_from_another_ractor
    ref = make_registered_weakref
    assert_predicate(ref, :weakref_alive?)

    assert_equal(true, Ractor.new { Bug::GC.unregister_static; true }.value)

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

  def test_verify_internal_consistency_with_ractor_stored_values
    omit "needs GC.verify_internal_consistency" unless GC.respond_to?(:verify_internal_consistency)
    Bug::GC.register_static(0)

    port = Ractor::Port.new
    r = Ractor.new(port) do |port|
      Bug::GC.assign_static(Ractor.make_shareable("shareable".dup))
      port.send(:stored)
      Ractor.receive
    end
    port.receive
    GC.verify_internal_consistency

    Bug::GC.assign_static("main owns this".dup)
    GC.verify_internal_consistency

    r.send(:done)
    r.value
  ensure
    Bug::GC.assign_static(0)
    Bug::GC.unregister_static
  end

  def test_verify_internal_consistency_reports_foreign_unshareable
    omit "needs GC.verify_internal_consistency" unless GC.respond_to?(:verify_internal_consistency)
    assert_in_out_err([], <<~RUBY, [], /registered address .* unshareable object owned by another Ractor/, success: true)
      require '-test-/gc/register'
      Bug::GC.register_static(0)
      port = Ractor::Port.new
      Ractor.new(port) do |port|
        Bug::GC.assign_static("foreign".dup)
        port.send(:stored)
        Ractor.receive
      end
      port.receive
      GC.verify_internal_consistency
    RUBY
  end
end
