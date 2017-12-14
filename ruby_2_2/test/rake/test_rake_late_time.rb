require File.expand_path('../helper', __FILE__)

class TestRakeLateTime < Rake::TestCase
  def test_late_time_comparisons
    late = Rake::LATE
    assert_equal late, late
    assert late >= Time.now
    assert late > Time.now
    assert late != Time.now
    assert Time.now < late
    assert Time.now <= late
    assert Time.now != late
  end

  def test_to_s
    assert_equal '<LATE TIME>', Rake::LATE.to_s
  end
end
