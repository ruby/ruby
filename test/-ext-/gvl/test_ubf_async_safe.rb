# frozen_string_literal: true
class TestUbfAsyncSafe < Test::Unit::TestCase
  def test_ubf_async_safe
    omit 'need fork for single-threaded test' unless Process.respond_to?(:fork)
    IO.pipe do |r, w|
      pid = fork do
        require '-test-/gvl/call_without_gvl'
        r.close
        trap(:INT) { exit!(0) }
        Bug::Thread.ubf_async_safe(w.fileno)
        exit!(1)
      end
      w.close
      assert IO.select([r], nil, nil, 30), 'child did not become ready'
      Process.kill(:INT, pid)
      _, st = Process.waitpid2(pid)
      assert_predicate st, :success?, ':INT signal triggered exit'
    end
  end
end
