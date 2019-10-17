# frozen_string_literal: true
require 'test/unit'
require 'observer'

class TestObserver < Test::Unit::TestCase
  class TestObservable
    include Observable

    def notify(*args)
      changed
      notify_observers(*args)
    end
  end

  class TestWatcher
    def initialize(observable)
      @notifications = []
      observable.add_observer(self)
    end

    attr_reader :notifications

    def update(*args)
      @notifications << args
    end
  end

  def test_observers
    observable = TestObservable.new

    assert_equal(0, observable.count_observers)

    watcher1 = TestWatcher.new(observable)

    assert_equal(1, observable.count_observers)

    observable.notify("test", 123)

    watcher2 = TestWatcher.new(observable)

    assert_equal(2, observable.count_observers)

    observable.notify(42)

    assert_equal([["test", 123], [42]], watcher1.notifications)
    assert_equal([[42]], watcher2.notifications)

    observable.delete_observer(watcher1)

    assert_equal(1, observable.count_observers)

    observable.notify(:cats)

    assert_equal([["test", 123], [42]], watcher1.notifications)
    assert_equal([[42], [:cats]], watcher2.notifications)

    observable.delete_observers

    assert_equal(0, observable.count_observers)

    observable.notify("nope")

    assert_equal([["test", 123], [42]], watcher1.notifications)
    assert_equal([[42], [:cats]], watcher2.notifications)
  end
end
