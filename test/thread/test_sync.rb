# frozen_string_literal: false
require 'test/unit'
require 'sync'
require 'timeout'

class SyncTest < Test::Unit::TestCase
  class Tester
    include Sync_m
  end

  def test_sync_lock_and_wakeup
    tester = Tester.new

    tester.sync_lock(:EX)

    t = Thread.new { tester.sync_lock(:EX) }

    sleep 0.1 until t.stop?
    t.wakeup
    sleep 0.1 until t.stop?

    assert_equal(tester.sync_waiting.uniq, tester.sync_waiting)
  ensure
    t.kill
    t.join
  end

  def test_sync_upgrade_and_wakeup
    tester = Tester.new
    tester.sync_lock(:SH)

    t = Thread.new do
      tester.sync_lock(:SH)
      tester.sync_lock(:EX)
    end

    sleep 0.1 until t.stop?
    t.wakeup
    sleep 0.1 until t.stop?

    tester.sync_upgrade_waiting.each { |ary|
      assert(!tester.sync_waiting.include?(ary[0]))
    }
    assert_equal(tester.sync_waiting.uniq, tester.sync_waiting)
    assert_equal(tester.sync_waiting, [])
  ensure
    t.kill
    t.join
  end

  def test_sync_lock_and_raise
    tester= Tester.new
    tester.sync_lock(:EX)

    t = Thread.new {
      assert_raise(RuntimeError) {
        tester.sync_lock(:EX)
      }
    }

    sleep 0.1 until t.stop?
    sleep 1 if RubyVM::MJIT.enabled? # t.stop? behaves unexpectedly with --jit-wait
    t.raise
    t.join

    assert_equal(tester.sync_waiting.uniq, tester.sync_waiting)
    assert_equal(tester.sync_waiting, [])
  end
end
