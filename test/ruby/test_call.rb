require 'test/unit'

$KCODE = 'none'

class TestCall < Test::Unit::TestCase
  def aaa(a, b=100, *rest)
    res = [a, b]
    res += rest if rest
    return res
  end

  def test_call
    begin
      aaa()				# need at least 1 arg
      assert(false)
    rescue
      assert(true)
    end
    
    begin
      aaa				# no arg given (exception raised)
      assert(false)
    rescue
      assert(true)
    end
    
    assert(aaa(1) == [1, 100])
    assert(aaa(1, 2) == [1, 2])
    assert(aaa(1, 2, 3, 4) == [1, 2, 3, 4])
    assert(aaa(1, *[2, 3, 4]) == [1, 2, 3, 4])
  end
end
