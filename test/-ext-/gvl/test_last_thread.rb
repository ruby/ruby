# frozen_string_literal: false
class TestLastThread < Test::Unit::TestCase

  # [Bug #11237]
  def test_last_thread
    assert_separately([], <<-"end;") #do
      require '-test-/gvl/call_without_gvl'

      Thread.new {
        sleep 0.2
      }

      t0 = Time.now
      Bug::Thread.runnable_sleep 1
      t1 = Time.now
      t = t1 - t0

      assert_in_delta(1.0, t, 0.16)
    end;
  end
end

