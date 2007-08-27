require 'test/unit'

class TestThread < Test::Unit::TestCase
  def test_mutex_synchronize
    m = Mutex.new
    r = 0
    max = 100
    (1..max).map{
      Thread.new{
        i=0
        while i<max*max
          i+=1
          m.synchronize{
            r += 1
          }
        end
      }
    }.each{|e|
      e.join
    }
    assert_equal(max * max * max, r)
  end
end

