require 'test/unit'

$KCODE = 'none'

class TestArray < Test::Unit::TestCase
  def test_array
    assert_equal([1, 2] + [3, 4], [1, 2, 3, 4])
    assert_equal([1, 2] * 2, [1, 2, 1, 2])
    assert_equal([1, 2] * ":", "1:2")
    
    assert_equal([1, 2].hash, [1, 2].hash)
    
    assert_equal([1,2,3] & [2,3,4], [2,3])
    assert_equal([1,2,3] | [2,3,4], [1,2,3,4])
    assert_equal([1,2,3] - [2,3], [1])
    
    $x = [0, 1, 2, 3, 4, 5]
    assert_equal($x[2], 2)
    assert_equal($x[1..3], [1, 2, 3])
    assert_equal($x[1,3], [1, 2, 3])
    
    $x[0, 2] = 10
    assert($x[0] == 10 && $x[1] == 2)
      
    $x[0, 0] = -1
    assert($x[0] == -1 && $x[1] == 10)
    
    $x[-1, 1] = 20
    assert($x[-1] == 20 && $x.pop == 20)
  end

  def test_array_andor
    assert_equal(([1,2,3]&[2,4,6]), [2])
    assert_equal(([1,2,3]|[2,4,6]), [1,2,3,4,6])
  end
    
  def test_compact
    $x = [nil, 1, nil, nil, 5, nil, nil]
    $x.compact!
    assert_equal($x, [1, 5])
  end

  def test_uniq
    $x = [1, 1, 4, 2, 5, 4, 5, 1, 2]
    $x.uniq!
    assert_equal($x, [1, 4, 2, 5])
    
    # empty?
    assert(!$x.empty?)
    $x = []
    assert($x.empty?)
  end

  def test_sort
    $x = ["it", "came", "to", "pass", "that", "..."]
    $x = $x.sort.join(" ")
    assert_equal($x, "... came it pass that to")
    $x = [2,5,3,1,7]
    $x.sort!{|a,b| a<=>b}		# sort with condition
    assert_equal($x, [1,2,3,5,7])
    $x.sort!{|a,b| b-a}		# reverse sort
    assert_equal($x, [7,5,3,2,1])
  end

  def test_split
    $x = "The Boassert of Mormon"
    assert_equal($x.split(//).reverse!.join, $x.reverse)
    assert_equal($x.reverse, $x.reverse!)
    assert_equal("1 byte string".split(//).reverse.join(":"), "g:n:i:r:t:s: :e:t:y:b: :1")
    $x = "a b c  d"
    assert_equal($x.split, ['a', 'b', 'c', 'd'])
    assert_equal($x.split(' '), ['a', 'b', 'c', 'd'])
  end

  def test_misc
    assert(defined? "a".chomp)
    assert_equal("abc".scan(/./), ["a", "b", "c"])
    assert_equal("1a2b3c".scan(/(\d.)/), [["1a"], ["2b"], ["3c"]])
    # non-greedy match
    assert_equal("a=12;b=22".scan(/(.*?)=(\d*);?/), [["a", "12"], ["b", "22"]])
    
    $x = [1]
    assert_equal(($x * 5).join(":"), '1:1:1:1:1')
    assert_equal(($x * 1).join(":"), '1')
    assert_equal(($x * 0).join(":"), '')
    
    *$x = *(1..7).to_a
    assert_equal($x.size, 7)
    assert_equal($x, [1, 2, 3, 4, 5, 6, 7])
    
    $x = [1,2,3]
    $x[1,0] = $x
    assert_equal($x, [1,1,2,3,2,3])
    
    $x = [1,2,3]
    $x[-1,0] = $x
    assert_equal($x, [1,2,1,2,3,3])
    
    $x = [1,2,3]
    $x.concat($x)
    assert_equal($x, [1,2,3,1,2,3])
  end
end
