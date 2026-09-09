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

  def test_unregister_address_from_another_ractor
    alive = 5.times.count do
      ref = Thread.new {
        v = "main owns this".dup
        Bug::GC.register_static(v)
        WeakRef.new(v)
      }.value
      assert_predicate(ref, :weakref_alive?)

      assert_equal(true, Ractor.new { Bug::GC.unregister_static; true }.value)

      3.times do
        GC.start(full_mark: true)
        break unless ref.weakref_alive?
      end
      ref.weakref_alive?
    end
    assert_operator(alive, :<, 5, "value stayed alive after unregister in every trial")
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

  def test_ractor_registered_value_survives_fork
    omit "fork not supported" unless Process.respond_to?(:fork)
    assert_separately([], <<~'RUBY')
      Warning[:experimental] = false
      require '-test-/gc/register'

      port = Ractor::Port.new
      # Not joined: the registration must stay with the dead Ractor until
      # ractor_free, and keeping r referenced prevents an early ractor_free.
      r = Ractor.new(port) { |port|
        Bug::GC.register_static("MARKER" * 10)
        port.send(:ok)
      }
      port.receive

      err = "#{ENV['TMPDIR'] || '/tmp'}/reg_fork_#{Process.pid}.log"
      pid = fork do
        $stderr.reopen(err, "w")
        GC.start
        100_000.times { "x" * 100 }
        exit!(Bug::GC.static_slot_eq?("MARKER" * 10) ? 0 : 1)
      end
      _, status = Process.wait2(pid)
      unless status.success?
        detail = File.exist?(err) ? File.read(err) : ""
        flunk(detail.empty? ? "registered value lost after fork+GC (#{status})" : detail)
      end
      File.unlink(err)
      r.value  # joins only after the scenario ran; keeps the wrapper alive until then
    RUBY
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
