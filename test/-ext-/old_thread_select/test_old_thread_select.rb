require 'test/unit'

class TestOldThreadSelect < Test::Unit::TestCase
  require '-test-/old_thread_select/old_thread_select'

  def with_pipe
    r, w = IO.pipe
    begin
      yield r, w
    ensure
      r.close unless r.closed?
      w.close unless w.closed?
    end
  end

  def test_old_select_read_timeout
    with_pipe do |r, w|
      t0 = Time.now
      rc = IO.old_thread_select([r.fileno], nil, nil, 0.001)
      diff = Time.now - t0
      assert_equal 0, rc
      assert diff > 0.001, "returned too early"
    end
  end

  def test_old_select_read_write_check
    with_pipe do |r, w|
      w.syswrite('.')
      rc = IO.old_thread_select([r.fileno], nil, nil, nil)
      assert_equal 1, rc

      rc = IO.old_thread_select([r.fileno], [w.fileno], nil, nil)
      assert_equal 2, rc

      assert_equal '.', r.read(1)

      rc = IO.old_thread_select([r.fileno], [w.fileno], nil, nil)
      assert_equal 1, rc
    end
  end

  def test_old_select_signal_safe
    return unless Process.respond_to?(:kill)
    received = false
    trap(:INT) { received = true }
    main = Thread.current
    thr = Thread.new do
      Thread.pass until main.stop?
      Process.kill(:INT, $$)
      true
    end

    rc = nil
    t0 = Time.now
    with_pipe do |r,w|
      assert_nothing_raised do
        rc = IO.old_thread_select([r.fileno], nil, nil, 1)
      end
    end

    diff = Time.now - t0
    assert diff >= 1.0, "interrupted or short wait"
    assert_equal 0, rc
    assert_equal true, thr.value
    assert received, "SIGINT not received"
    ensure
      trap(:INT, "DEFAULT")
  end
end
