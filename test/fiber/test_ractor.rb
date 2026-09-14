# frozen_string_literal: true
require "test/unit"
require "fiber"
require_relative "scheduler"

class TestFiberCurrentRactor < Test::Unit::TestCase
  def setup
    omit unless defined? Ractor
  end

  def test_ractor_shareable
    assert_separately([], "#{<<~"begin;"}\n#{<<~'end;'}")
    begin;
      $VERBOSE = nil
      require "fiber"
      r = Ractor.new do
        Fiber.new do
          Fiber.current.class
        end.resume
      end
      assert_equal(Fiber, r.value)
    end;
  end

  def test_port_receive_does_not_block_other_fibers
    scheduler = Scheduler.new
    Fiber.set_scheduler(scheduler)

    port = Ractor::Port.new
    sender = Ractor.new(port) do |port|
      sleep 0.1
      port << :message
    end
    events = []

    Fiber.schedule do
      events << :receive_started
      events << port.receive
    end

    Fiber.schedule do
      events << :other_fiber
    end

    scheduler.run
    sender.join

    assert_equal [:receive_started, :other_fiber, :message], events
  ensure
    Fiber.set_scheduler(nil) if Fiber.scheduler
  end

  def test_port_receive_timeout_does_not_block_other_fibers
    scheduler = Scheduler.new
    Fiber.set_scheduler(scheduler)

    port = Ractor::Port.new
    events = []

    Fiber.schedule do
      events << :receive_started
      events << port.receive(timeout: 0.01)
    end

    Fiber.schedule do
      events << :other_fiber
    end

    scheduler.run

    assert_equal [:receive_started, :other_fiber, nil], events
  ensure
    Fiber.set_scheduler(nil) if Fiber.scheduler
  end

  def test_port_close_unblocks_waiting_fiber
    scheduler = Scheduler.new
    Fiber.set_scheduler(scheduler)

    port = Ractor::Port.new
    error = nil

    Fiber.schedule do
      port.receive
    rescue Ractor::ClosedError => exception
      error = exception
    end

    Fiber.schedule do
      port.close
    end

    scheduler.run

    assert_kind_of Ractor::ClosedError, error
  ensure
    Fiber.set_scheduler(nil) if Fiber.scheduler
  end

  def test_multiple_fibers_can_wait_for_ports
    scheduler = Scheduler.new
    Fiber.set_scheduler(scheduler)

    ports = 2.times.map { Ractor::Port.new }
    senders = ports.map.with_index do |port, index|
      Ractor.new(port, index) do |port, index|
        Ractor.receive
        port << index
      end
    end
    events = []

    ports.each_with_index do |port, index|
      Fiber.schedule do
        events << [:waiting, index]
        events << [:received, port.receive]
      end
    end

    Fiber.schedule do
      events << :other_fiber
      senders.each { |sender| sender << nil }
    end

    scheduler.run
    senders.each(&:join)

    assert_equal [[:waiting, 0], [:waiting, 1], :other_fiber], events.take(3)
    assert_equal [[:received, 0], [:received, 1]], events.drop(3).sort
  ensure
    Fiber.set_scheduler(nil) if Fiber.scheduler
  end

  def test_ractor_select_does_not_block_other_fibers
    scheduler = Scheduler.new
    Fiber.set_scheduler(scheduler)

    port = Ractor::Port.new
    sender = Ractor.new(port) do |port|
      sleep 0.1
      port << :message
    end
    events = []

    Fiber.schedule do
      events << :select_started
      events << Ractor.select(port)
    end

    Fiber.schedule do
      events << :other_fiber
    end

    scheduler.run
    sender.join

    assert_equal [:select_started, :other_fiber, [port, :message]], events
  ensure
    Fiber.set_scheduler(nil) if Fiber.scheduler
  end
end
