require File.expand_path('../helper', __FILE__)

require 'rake/thread_history_display'

class TestThreadHistoryDisplay < Rake::TestCase
  def setup
    super
    @time = 1_000_000
    @stats = []
    @display = Rake::ThreadHistoryDisplay.new(@stats)
  end

  def test_banner
    out, _ = capture_io do
      @display.show
    end
    assert_match(/Job History/i, out)
  end

  def test_item_queued
    @stats << event(:item_queued,  :item_id => 123)
    out, _ = capture_io do
      @display.show
    end
    assert_match(/^ *1000000 +A +item_queued +item_id:1$/, out)
  end

  def test_item_dequeued
    @stats << event(:item_dequeued,  :item_id => 123)
    out, _ = capture_io do
      @display.show
    end
    assert_match(/^ *1000000 +A +item_dequeued +item_id:1$/, out)
  end

  def test_multiple_items
    @stats << event(:item_queued,  :item_id => 123)
    @stats << event(:item_queued,  :item_id => 124)
    out, _ = capture_io do
      @display.show
    end
    assert_match(/^ *1000000 +A +item_queued +item_id:1$/, out)
    assert_match(/^ *1000001 +A +item_queued +item_id:2$/, out)
  end

  def test_waiting
    @stats << event(:waiting, :item_id => 123)
    out, _ = capture_io do
      @display.show
    end
    assert_match(/^ *1000000 +A +waiting +item_id:1$/, out)
  end

  def test_continue
    @stats << event(:continue, :item_id => 123)
    out, _ = capture_io do
      @display.show
    end
    assert_match(/^ *1000000 +A +continue +item_id:1$/, out)
  end

  def test_thread_deleted
    @stats << event(
      :thread_deleted,
      :deleted_thread => 123_456,
      :thread_count => 12)
    out, _ = capture_io do
      @display.show
    end
    assert_match(
      /^ *1000000 +A +thread_deleted( +deleted_thread:B| +thread_count:12){2}$/,
      out)
  end

  def test_thread_created
    @stats << event(
      :thread_created,
      :new_thread => 123_456,
      :thread_count => 13)
    out, _ = capture_io do
      @display.show
    end
    assert_match(
      /^ *1000000 +A +thread_created( +new_thread:B| +thread_count:13){2}$/,
      out)
  end

  private

  def event(type, data = {})
    result = {
      :event => type,
      :time  => @time / 1_000_000.0,
      :data  => data,
      :thread => Thread.current.object_id
    }
    @time += 1
    result
  end

end
