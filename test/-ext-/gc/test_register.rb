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
    # assert_separately: keep the test-all process Ractor-free (Bug #22263)
    assert_separately([], <<~RUBY)
      Warning[:experimental] = false
      require '-test-/gc/register'

      r = Ractor.new { Bug::GC.register_static("registered in child".dup) }
      assert_equal(true, r.value)

      2.times { GC.start(full_mark: true) }
      assert_equal("registered in child", Bug::GC.static_slot_value)
    RUBY
  end

  def test_unregister_address_from_another_ractor
    assert_separately([], <<~RUBY)
      Warning[:experimental] = false
      require 'weakref'
      require '-test-/gc/register'

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
    RUBY
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
    assert_separately([], <<~RUBY)
      Warning[:experimental] = false
      require '-test-/gc/register'

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
    RUBY
  end

  def test_verify_internal_consistency_fails_on_foreign_unshareable_store
    omit "needs GC.verify_internal_consistency with the registered-address check" unless
      GC.respond_to?(:verify_internal_consistency) && Bug::GC.registered_address_check_enabled?
    assert_in_out_err([], <<~RUBY, [], /registered address .* changed since registration to an unshareable object owned by another Ractor/, success: false)
      require '-test-/gc/register'
      Bug::GC.register_static(0)
      port = Ractor::Port.new
      Ractor.new(port) do |port|
        child_string = "foreign".dup
        Bug::GC.assign_static(child_string)
        port.send(:stored)
        Ractor.receive
        child_string
      end
      port.receive
      GC.verify_internal_consistency
    RUBY
  end

  def test_verify_internal_consistency_ignores_registration_time_value
    omit "needs the registered-address check" unless Bug::GC.registered_address_check_enabled?
    assert_separately([], <<~RUBY)
      Warning[:experimental] = false
      require '-test-/gc/register'

      port = Ractor::Port.new
      r = Ractor.new(port) do |port|
        child_string = "registered in child".dup
        Bug::GC.assign_static(child_string)
        port.send(:stored)
        Ractor.receive
        child_string
      end
      port.receive

      # The slot already holds the child's string at registration time, so the
      # registration-time snapshot matches and the verifier must not fail.
      Bug::GC.register_current_static
      GC.verify_internal_consistency
      Bug::GC.unregister_static

      r.send(:done)
      r.value
    RUBY
  end

  def test_verify_internal_consistency_ignores_cross_ractor_duplicate_registration
    omit "needs the registered-address check" unless Bug::GC.registered_address_check_enabled?
    assert_separately([], <<~RUBY)
      Warning[:experimental] = false
      require '-test-/gc/register'

      Bug::GC.register_static(0)

      port = Ractor::Port.new
      r = Ractor.new(port) do |port|
        child_string = "registered in child".dup
        Bug::GC.register_static(child_string)
        port.send(:stored)
        Ractor.receive
        Bug::GC.unregister_static
        port.send(:unregistered)
        child_string
      end
      port.receive

      # Main's entry is stale (initial value 0, current value owned by the child),
      # but the child registrant owns the value, so the verifier must not fail.
      GC.verify_internal_consistency

      r.send(:done)
      port.receive
      Bug::GC.unregister_static
      r.value
    RUBY
  end

  def test_verify_internal_consistency_with_many_registered_addresses_and_gc_stress
    omit "needs GC.verify_internal_consistency" unless GC.respond_to?(:verify_internal_consistency)
    assert_separately([], <<~RUBY)
      Warning[:experimental] = false
      require '-test-/gc/register'
      port = Ractor::Port.new
      r = Ractor.new(port) { |port| port.send(:ready); Ractor.receive }
      17.times { Bug::GC.register_static(0) }
      port.receive
      begin
        GC.stress = true
        GC.verify_internal_consistency
      ensure
        GC.stress = false
        17.times { Bug::GC.unregister_static }
      end

      r.send(:done)
      r.value
    RUBY
  end
end
