require 'test/unit'

class TestArray < Test::Unit::TestCase
  def test_array
    assert_equal([1, 2, 3, 4], [1, 2] + [3, 4])
    assert_equal([1, 2, 1, 2], [1, 2] * 2)
    assert_equal("1:2", [1, 2] * ":")

    assert_equal([1, 2].hash, [1, 2].hash)

    assert_equal([2,3], [1,2,3] & [2,3,4])
    assert_equal([1,2,3,4], [1,2,3] | [2,3,4])
    assert_equal([1,2,3] - [2,3], [1])

    x = [0, 1, 2, 3, 4, 5]
    assert_equal(2, x[2])
    assert_equal([1, 2, 3], x[1..3])
    assert_equal([1, 2, 3], x[1,3])

    x[0, 2] = 10
    assert(x[0] == 10 && x[1] == 2)

    x[0, 0] = -1
    assert(x[0] == -1 && x[1] == 10)

    x[-1, 1] = 20
    assert(x[-1] == 20 && x.pop == 20)
  end

  def test_array_andor
    assert_equal([2], ([1,2,3]&[2,4,6]))
    assert_equal([1,2,3,4,6], ([1,2,3]|[2,4,6]))
  end

  def test_compact
    x = [nil, 1, nil, nil, 5, nil, nil]
    x.compact!
    assert_equal([1, 5], x)
  end

  def test_uniq
    x = [1, 1, 4, 2, 5, 4, 5, 1, 2]
    x.uniq!
    assert_equal([1, 4, 2, 5], x)

    # empty?
    assert(!x.empty?)
    x = []
    assert(x.empty?)
  end

  def test_sort
    x = ["it", "came", "to", "pass", "that", "..."]
    x = x.sort.join(" ")
    assert_equal("... came it pass that to", x)
    x = [2,5,3,1,7]
    x.sort!{|a,b| a<=>b}		# sort with condition
    assert_equal([1,2,3,5,7], x)
    x.sort!{|a,b| b-a}		# reverse sort
    assert_equal([7,5,3,2,1], x)
  end

  def test_split
    x = "The Boassert of Mormon"
    assert_equal(x.reverse, x.split(//).reverse!.join)
    assert_equal(x.reverse, x.reverse!)
    assert_equal("g:n:i:r:t:s: :e:t:y:b: :1", "1 byte string".split(//).reverse.join(":"))
    x = "a b c  d"
    assert_equal(['a', 'b', 'c', 'd'], x.split)
    assert_equal(['a', 'b', 'c', 'd'], x.split(' '))
  end

  def test_misc
    assert(defined? "a".chomp)
    assert_equal(["a", "b", "c"], "abc".scan(/./))
    assert_equal([["1a"], ["2b"], ["3c"]], "1a2b3c".scan(/(\d.)/))
    # non-greedy match
    assert_equal([["a", "12"], ["b", "22"]], "a=12;b=22".scan(/(.*?)=(\d*);?/))

    x = [1]
    assert_equal('1:1:1:1:1', (x * 5).join(":"))
    assert_equal('1', (x * 1).join(":"))
    assert_equal('', (x * 0).join(":"))

    *x = *(1..7).to_a
    assert_equal(7, x.size)
    assert_equal([1, 2, 3, 4, 5, 6, 7], x)

    x = [1,2,3]
    x[1,0] = x
    assert_equal([1,1,2,3,2,3], x)

    x = [1,2,3]
    x[-1,0] = x
    assert_equal([1,2,1,2,3,3], x)

    x = [1,2,3]
    x.concat(x)
    assert_equal([1,2,3,1,2,3], x)
  end
end
