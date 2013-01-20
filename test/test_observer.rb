require 'test/unit'
require 'observer'

class TestObserver < Test::Unit::TestCase

  class MockObservable
    include Observable
  end

  class MockObserver
    attr_reader :updates
    def initialize
      @updates = []
    end
    def update *args
      updates.push(args)
    end
  end

  def setup
    @observable = MockObservable.new
    @observer = MockObserver.new
  end

  def test_count_observers
    assert_equal(0, @observable.count_observers)
    @observable.add_observer(@observer)
    assert_equal(1, @observable.count_observers)
    9.times { @observable.add_observer(MockObserver.new) }
    assert_equal(10, @observable.count_observers)
    @observable.delete_observer(@observer)
    assert_equal(9, @observable.count_observers)
    @observable.delete_observers()
    assert_equal(0, @observable.count_observers)
  end

  def test_changed
    @observable = MockObservable.new
    assert(!@observable.changed?)
    @observable.changed
    assert(@observable.changed?)
    @observable.notify_observers
    assert(!@observable.changed?)
    @observable.changed(true)
    assert(@observable.changed?)
    @observable.changed(false)
    assert(!@observable.changed?)
  end

  def test_notify
    @observable.add_observer(@observer)
    @observable.changed
    @observable.notify_observers()
    @observable.changed
    @observable.notify_observers(1)
    @observable.notify_observers(:not_changed)
    @observable.changed
    @observable.notify_observers(2, 3)
    assert_equal([[], [1], [2, 3]], @observer.updates)
  end

  def test_add_delete_observer
    @observable.changed
    @observable.notify_observers(1)
    @observable.add_observer(@observer)
    @observable.changed
    @observable.notify_observers(2)
    @observable.delete_observer(@observer)
    @observable.changed
    @observable.notify_observers(3)
    assert_equal([[2]], @observer.updates)
  end

  def test_add_custom_observer
    custom_observer = []
    @observable.add_observer(custom_observer, :push)
    @observable.changed
    @observable.notify_observers(1,2,3)
    assert_equal([1, 2, 3], custom_observer)
    @observable.delete_observer(custom_observer)
    @observable.changed
    @observable.notify_observers(4,5)
    assert_equal([1, 2, 3], custom_observer)
  end

end
