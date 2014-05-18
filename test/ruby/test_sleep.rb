require 'test/unit'
require 'etc'

class TestSleep < Test::Unit::TestCase
  def test_sleep_5sec
    GC.disable
    start = Time.now
    sleep 5
    slept = Time.now-start
    bottom =
      case RUBY_PLATFORM
      when /linux/
        4.98 if (Etc.uname[:release].split('.').map(&:to_i)<=>[2,6,18]) <= 0
      when /mswin|mingw/
        4.98
      end
    bottom ||= 5.0
    assert_operator(slept, :>=, bottom)
    assert_operator(slept, :<=, 6.0, "[ruby-core:18015]: longer than expected")
  ensure
    GC.enable
  end
end
