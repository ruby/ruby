
require 'test/unit'

class TestBacktrace < Test::Unit::TestCase
  def test_exception
    bt = Fiber.new{
      begin
        raise
      rescue => e
        e.backtrace
      end
    }.resume
    assert_equal(1, bt.size)
    assert_match(/.+:\d+:.+/, bt[0])
  end

  def test_caller_lev
    cs = []
    Fiber.new{
      Proc.new{
        cs << caller(0)
        cs << caller(1)
        cs << caller(2)
        cs << caller(3)
        cs << caller(4)
        cs << caller(5)
      }.call
    }.resume
    assert_equal(3, cs[0].size)
    assert_equal(2, cs[1].size)
    assert_equal(1, cs[2].size)
    assert_equal(0, cs[3].size)
    assert_equal(nil, cs[4])

    #
    max = 20
    rec = lambda{|n|
      if n > 0
        1.times{
          rec[n-1]
        }
      else
        max.times{|i|
          total_size = caller(0).size
          c = caller(i)
          if c
            assert_equal(total_size - i, caller(i).size, "[ruby-dev:45673]")
          end
        }
      end
    }
    bt = Fiber.new{
      rec[max]
    }.resume
  end
end

