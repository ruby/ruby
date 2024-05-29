# coding: US-ASCII
# frozen_string_literal: false
require 'test/unit'
require "delegate"
require "rbconfig/sizeof"

class TestArray < Test::Unit::TestCase
  def setup
    @verbose = $VERBOSE
    @cls = Array
  end

  def teardown
    $VERBOSE = @verbose
  end

  def assert_equal_instance(x, y, *msg)
    assert_equal(x, y, *msg)
    assert_instance_of(x.class, y)
  end

  def test_percent_i
    assert_equal([:foo, :bar], %i[foo bar])
    assert_equal([:"\"foo"], %i["foo])
  end

  def test_percent_I
    x = 10
    assert_equal([:foo, :b10], %I[foo b#{x}])
    assert_equal([:"\"foo10"], %I["foo#{x}])
  end

  def test_0_literal
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
    assert_equal([3, 4, 5], x[3..])
    assert_equal([0, 1, 2], x[..2])
    assert_equal([0, 1], x[...2])

    x[0, 2] = 10
    assert_equal([10, 2, 3, 4, 5], x)

    x[0, 0] = -1
    assert_equal([-1, 10, 2, 3, 4, 5], x)

    x[-1, 1] = 20
    assert_equal(20, x[-1])
    assert_equal(20, x.pop)
  end

  def test_array_andor_0
    assert_equal([2], ([1,2,3]&[2,4,6]))
    assert_equal([1,2,3,4,6], ([1,2,3]|[2,4,6]))
  end

  def test_compact_0
    a = [nil, 1, nil, nil, 5, nil, nil]
    assert_equal [1, 5], a.compact
    assert_equal [nil, 1, nil, nil, 5, nil, nil], a
    a.compact!
    assert_equal [1, 5], a
  end

  def test_uniq_0
    x = [1, 1, 4, 2, 5, 4, 5, 1, 2]
    x.uniq!
    assert_equal([1, 4, 2, 5], x)
  end

  def test_empty_0
    assert_equal true, [].empty?
    assert_equal false, [1].empty?
    assert_equal false, [1, 1, 4, 2, 5, 4, 5, 1, 2].empty?
  end

  def test_sort_0
    x = ["it", "came", "to", "pass", "that", "..."]
    x = x.sort.join(" ")
    assert_equal("... came it pass that to", x)
    x = [2,5,3,1,7]
    x.sort!{|a,b| a<=>b}		# sort with condition
    assert_equal([1,2,3,5,7], x)
    x.sort!{|a,b| b-a}		# reverse sort
    assert_equal([7,5,3,2,1], x)
  end

  def test_split_0
    x = "The Book of Mormon"
    assert_equal(x.reverse, x.split(//).reverse!.join)
    assert_equal(x.reverse, x.reverse!)
    assert_equal("g:n:i:r:t:s: :e:t:y:b: :1", "1 byte string".split(//).reverse.join(":"))
    x = "a b c  d"
    assert_equal(['a', 'b', 'c', 'd'], x.split)
    assert_equal(['a', 'b', 'c', 'd'], x.split(' '))
  end

  def test_misc_0
    assert(defined? "a".chomp, '"a".chomp is not defined')
    assert_equal(["a", "b", "c"], "abc".scan(/./))
    assert_equal([["1a"], ["2b"], ["3c"]], "1a2b3c".scan(/(\d.)/))
    # non-greedy match
    assert_equal([["a", "12"], ["b", "22"]], "a=12;b=22".scan(/(.*?)=(\d*);?/))

    x = [1]
    assert_equal('1:1:1:1:1', (x * 5).join(":"))
    assert_equal('1', (x * 1).join(":"))
    assert_equal('', (x * 0).join(":"))

    assert_instance_of(Array, (@cls[] * 5))
    assert_instance_of(Array, (@cls[1] * 5))

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

    x = [1,2,3]
    x.clear
    assert_equal([], x)

    x = [1,2,3]
    y = x.dup
    x << 4
    y << 5
    assert_equal([1,2,3,4], x)
    assert_equal([1,2,3,5], y)
  end

  def test_beg_end_0
    x = [1, 2, 3, 4, 5]

    assert_equal(1, x.first)
    assert_equal([1], x.first(1))
    assert_equal([1, 2, 3], x.first(3))
    assert_raise_with_message(ArgumentError, /0\.\.1/) {x.first(1, 2)}

    assert_equal(5, x.last)
    assert_equal([5], x.last(1))
    assert_equal([3, 4, 5], x.last(3))
    assert_raise_with_message(ArgumentError, /0\.\.1/) {x.last(1, 2)}

    assert_equal(1, x.shift)
    assert_equal([2, 3, 4], x.shift(3))
    assert_equal([5], x)
    assert_raise_with_message(ArgumentError, /0\.\.1/) {x.first(1, 2)}

    assert_equal([2, 3, 4, 5], x.unshift(2, 3, 4))
    assert_equal([1, 2, 3, 4, 5], x.unshift(1))
    assert_equal([1, 2, 3, 4, 5], x)

    assert_equal(5, x.pop)
    assert_equal([3, 4], x.pop(2))
    assert_equal([1, 2], x)
    assert_raise_with_message(ArgumentError, /0\.\.1/) {x.pop(1, 2)}

    assert_equal([1, 2, 3, 4], x.push(3, 4))
    assert_equal([1, 2, 3, 4, 5], x.push(5))
    assert_equal([1, 2, 3, 4, 5], x)
  end

  def test_find_all_0
    assert_respond_to([], :find_all)
    assert_respond_to([], :select)       # Alias
    assert_respond_to([], :filter)       # Alias
    assert_equal([], [].find_all{ |obj| obj == "foo"})

    x = ["foo", "bar", "baz", "baz", 1, 2, 3, 3, 4]
    assert_equal(["baz","baz"], x.find_all{ |obj| obj == "baz" })
    assert_equal([3,3], x.find_all{ |obj| obj == 3 })
  end

  def test_fill_0
    assert_equal([-1, -1, -1, -1, -1, -1], [0, 1, 2, 3, 4, 5].fill(-1))
    assert_equal([0, 1, 2, -1, -1, -1], [0, 1, 2, 3, 4, 5].fill(-1, 3))
    assert_equal([0, 1, 2, -1, -1, 5], [0, 1, 2, 3, 4, 5].fill(-1, 3, 2))
    assert_equal([0, 1, 2, -1, -1, -1, -1, -1], [0, 1, 2, 3, 4, 5].fill(-1, 3, 5))
    assert_equal([0, 1, -1, -1, 4, 5], [0, 1, 2, 3, 4, 5].fill(-1, 2, 2))
    assert_equal([0, 1, -1, -1, -1, -1, -1], [0, 1, 2, 3, 4, 5].fill(-1, 2, 5))
    assert_equal([0, 1, 2, 3, -1, 5], [0, 1, 2, 3, 4, 5].fill(-1, -2, 1))
    assert_equal([0, 1, 2, 3, -1, -1, -1], [0, 1, 2, 3, 4, 5].fill(-1, -2, 3))
    assert_equal([0, 1, 2, -1, -1, 5], [0, 1, 2, 3, 4, 5].fill(-1, 3..4))
    assert_equal([0, 1, 2, -1, 4, 5], [0, 1, 2, 3, 4, 5].fill(-1, 3...4))
    assert_equal([0, 1, -1, -1, -1, 5], [0, 1, 2, 3, 4, 5].fill(-1, 2..-2))
    assert_equal([0, 1, -1, -1, 4, 5], [0, 1, 2, 3, 4, 5].fill(-1, 2...-2))
    assert_equal([10, 11, 12, 13, 14, 15], [0, 1, 2, 3, 4, 5].fill{|i| i+10})
    assert_equal([0, 1, 2, 13, 14, 15], [0, 1, 2, 3, 4, 5].fill(3){|i| i+10})
    assert_equal([0, 1, 2, 13, 14, 5], [0, 1, 2, 3, 4, 5].fill(3, 2){|i| i+10})
    assert_equal([0, 1, 2, 13, 14, 15, 16, 17], [0, 1, 2, 3, 4, 5].fill(3, 5){|i| i+10})
    assert_equal([0, 1, 2, 13, 14, 5], [0, 1, 2, 3, 4, 5].fill(3..4){|i| i+10})
    assert_equal([0, 1, 2, 13, 4, 5], [0, 1, 2, 3, 4, 5].fill(3...4){|i| i+10})
    assert_equal([0, 1, 12, 13, 14, 5], [0, 1, 2, 3, 4, 5].fill(2..-2){|i| i+10})
    assert_equal([0, 1, 12, 13, 4, 5], [0, 1, 2, 3, 4, 5].fill(2...-2){|i| i+10})
    assert_equal([0, 1, 2, 13, 14, 15], [0, 1, 2, 3, 4, 5].fill(3..){|i| i+10})
    assert_equal([0, 1, 2, 13, 14, 15], [0, 1, 2, 3, 4, 5].fill(3...){|i| i+10})
  end

  # From rubicon

  def test_00_new
    a = @cls.new()
    assert_instance_of(@cls, a)
    assert_equal(0, a.length)
    assert_nil(a[0])
  end

  def test_01_square_brackets
    a = @cls[ 5, 4, 3, 2, 1 ]
    assert_instance_of(@cls, a)
    assert_equal(5, a.length)
    5.times { |i| assert_equal(5-i, a[i]) }
    assert_nil(a[6])
  end

  def test_AND # '&'
    assert_equal(@cls[1, 3], @cls[ 1, 1, 3, 5 ] & @cls[ 1, 2, 3 ])
    assert_equal(@cls[],     @cls[ 1, 1, 3, 5 ] & @cls[ ])
    assert_equal(@cls[],     @cls[  ]           & @cls[ 1, 2, 3 ])
    assert_equal(@cls[],     @cls[ 1, 2, 3 ]    & @cls[ 4, 5, 6 ])
  end

  def test_AND_big_array # '&'
    assert_equal(@cls[1, 3], @cls[ 1, 1, 3, 5 ]*64 & @cls[ 1, 2, 3 ]*64)
    assert_equal(@cls[],     @cls[ 1, 1, 3, 5 ]*64 & @cls[ ])
    assert_equal(@cls[],     @cls[  ]           & @cls[ 1, 2, 3 ]*64)
    assert_equal(@cls[],     @cls[ 1, 2, 3 ]*64 & @cls[ 4, 5, 6 ]*64)
  end

  def test_intersection
    assert_equal(@cls[1, 2], @cls[1, 2, 3].intersection(@cls[1, 2]))
    assert_equal(@cls[ ], @cls[1].intersection(@cls[ ]))
    assert_equal(@cls[ ], @cls[ ].intersection(@cls[1]))
    assert_equal(@cls[1], @cls[1, 2, 3].intersection(@cls[1, 2], @cls[1]))
    assert_equal(@cls[ ], @cls[1, 2, 3].intersection(@cls[1, 2], @cls[3]))
    assert_equal(@cls[ ], @cls[1, 2, 3].intersection(@cls[4, 5, 6]))
  end

  def test_intersection_big_array
    assert_equal(@cls[1, 2], (@cls[1, 2, 3] * 64).intersection(@cls[1, 2] * 64))
    assert_equal(@cls[ ], (@cls[1] * 64).intersection(@cls[ ]))
    assert_equal(@cls[ ], @cls[ ].intersection(@cls[1] * 64))
    assert_equal(@cls[1], (@cls[1, 2, 3] * 64).intersection((@cls[1, 2] * 64), (@cls[1] * 64)))
    assert_equal(@cls[ ], (@cls[1, 2, 3] * 64).intersection(@cls[4, 5, 6] * 64))
  end

  def test_MUL # '*'
    assert_equal(@cls[], @cls[]*3)
    assert_equal(@cls[1, 1, 1], @cls[1]*3)
    assert_equal(@cls[1, 2, 1, 2, 1, 2], @cls[1, 2]*3)
    assert_equal(@cls[], @cls[1, 2, 3] * 0)
    assert_raise(ArgumentError) { @cls[1, 2]*(-3) }

    assert_equal('1-2-3-4-5', @cls[1, 2, 3, 4, 5] * '-')
    assert_equal('12345',     @cls[1, 2, 3, 4, 5] * '')

  end

  def test_PLUS # '+'
    assert_equal(@cls[],     @cls[]  + @cls[])
    assert_equal(@cls[1],    @cls[1] + @cls[])
    assert_equal(@cls[1],    @cls[]  + @cls[1])
    assert_equal(@cls[1, 1], @cls[1] + @cls[1])
    assert_equal(@cls['cat', 'dog', 1, 2, 3], %w(cat dog) + (1..3).to_a)
  end

  def test_MINUS # '-'
    assert_equal(@cls[],  @cls[1] - @cls[1])
    assert_equal(@cls[1], @cls[1, 2, 3, 4, 5] - @cls[2, 3, 4, 5])
    assert_equal(@cls[1, 1, 1, 1], @cls[1, 2, 1, 3, 1, 4, 1, 5] - @cls[2, 3, 4, 5])
    assert_equal(@cls[1, 1],  @cls[1, 2, 1] - @cls[2])
    assert_equal(@cls[1, 2, 3], @cls[1, 2, 3] - @cls[4, 5, 6])
  end

  def test_MINUS_big_array # '-'
    assert_equal(@cls[1]*64, @cls[1, 2, 3, 4, 5]*64 - @cls[2, 3, 4, 5]*64)
    assert_equal(@cls[1, 1, 1, 1]*64, @cls[1, 2, 1, 3, 1, 4, 1, 5]*64 - @cls[2, 3, 4, 5]*64)
    a = @cls[]
    1000.times { a << 1 }
    assert_equal(1000, a.length)
    assert_equal(@cls[1] * 1000, a - @cls[2])
  end

  def test_difference
    assert_equal(@cls[],  @cls[1].difference(@cls[1]))
    assert_equal(@cls[1], @cls[1, 2, 3, 4, 5].difference(@cls[2, 3, 4, 5]))
    assert_equal(@cls[1, 1],  @cls[1, 2, 1].difference(@cls[2]))
    assert_equal(@cls[1, 1, 1, 1], @cls[1, 2, 1, 3, 1, 4, 1, 5].difference(@cls[2, 3, 4, 5]))
    assert_equal(@cls[], @cls[1, 2, 3, 4].difference(@cls[1], @cls[2], @cls[3], @cls[4]))
    a = [1]
    assert_equal(@cls[1], a.difference(@cls[2], @cls[2]))
    assert_equal(@cls[], a.difference(@cls[1]))
    assert_equal(@cls[1], a)
  end

  def test_difference_big_array
    assert_equal(@cls[1]*64, (@cls[1, 2, 3, 4, 5] * 64).difference(@cls[2, 3, 4] * 64, @cls[3, 5] * 64))
    assert_equal(@cls[1, 1, 1, 1]*64, (@cls[1, 2, 1, 3, 1, 4, 1, 5] * 64).difference(@cls[2, 3, 4, 5] * 64))
    a = @cls[1] * 1000
    assert_equal(@cls[1] * 1000, a.difference(@cls[2], @cls[2]))
    assert_equal(@cls[], a.difference(@cls[1]))
    assert_equal(@cls[1] * 1000, a)
  end

  def test_LSHIFT # '<<'
    a = @cls[]
    a << 1
    assert_equal(@cls[1], a)
    a << 2 << 3
    assert_equal(@cls[1, 2, 3], a)
    a << nil << 'cat'
    assert_equal(@cls[1, 2, 3, nil, 'cat'], a)
    a << a
    assert_equal(@cls[1, 2, 3, nil, 'cat', a], a)
  end

  def test_CMP # '<=>'
    assert_equal(0,  @cls[] <=> @cls[])
    assert_equal(0,  @cls[1] <=> @cls[1])
    assert_equal(0,  @cls[1, 2, 3, 'cat'] <=> @cls[1, 2, 3, 'cat'])
    assert_equal(-1, @cls[] <=> @cls[1])
    assert_equal(1,  @cls[1] <=> @cls[])
    assert_equal(-1, @cls[1, 2, 3] <=> @cls[1, 2, 3, 'cat'])
    assert_equal(1,  @cls[1, 2, 3, 'cat'] <=> @cls[1, 2, 3])
    assert_equal(-1, @cls[1, 2, 3, 'cat'] <=> @cls[1, 2, 3, 'dog'])
    assert_equal(1,  @cls[1, 2, 3, 'dog'] <=> @cls[1, 2, 3, 'cat'])
  end

  def test_EQUAL # '=='
    assert_operator(@cls[], :==, @cls[])
    assert_operator(@cls[1], :==, @cls[1])
    assert_operator(@cls[1, 1, 2, 2], :==, @cls[1, 1, 2, 2])
    assert_operator(@cls[1.0, 1.0, 2.0, 2.0], :==, @cls[1, 1, 2, 2])
  end

  def test_VERY_EQUAL # '==='
    assert_operator(@cls[], :===, @cls[])
    assert_operator(@cls[1], :===, @cls[1])
    assert_operator(@cls[1, 1, 2, 2], :===, @cls[1, 1, 2, 2])
    assert_operator(@cls[1.0, 1.0, 2.0, 2.0], :===, @cls[1, 1, 2, 2])
  end

  def test_AREF # '[]'
    a = @cls[*(1..100).to_a]

    assert_equal(1, a[0])
    assert_equal(100, a[99])
    assert_nil(a[100])
    assert_equal(100, a[-1])
    assert_equal(99,  a[-2])
    assert_equal(1,   a[-100])
    assert_nil(a[-101])
    assert_nil(a[-101,0])
    assert_nil(a[-101,1])
    assert_nil(a[-101,-1])
    assert_nil(a[10,-1])

    assert_equal(@cls[1],   a[0,1])
    assert_equal(@cls[100], a[99,1])
    assert_equal(@cls[],    a[100,1])
    assert_equal(@cls[100], a[99,100])
    assert_equal(@cls[100], a[-1,1])
    assert_equal(@cls[99],  a[-2,1])
    assert_equal(@cls[],    a[-100,0])
    assert_equal(@cls[1],   a[-100,1])

    assert_equal(@cls[10, 11, 12], a[9, 3])
    assert_equal(@cls[10, 11, 12], a[-91, 3])

    assert_equal(@cls[1],   a[0..0])
    assert_equal(@cls[100], a[99..99])
    assert_equal(@cls[],    a[100..100])
    assert_equal(@cls[100], a[99..200])
    assert_equal(@cls[100], a[-1..-1])
    assert_equal(@cls[99],  a[-2..-2])

    assert_equal(@cls[10, 11, 12], a[9..11])
    assert_equal(@cls[98, 99, 100], a[97..])
    assert_equal(@cls[1, 2, 3], a[..2])
    assert_equal(@cls[1, 2], a[...2])
    assert_equal(@cls[10, 11, 12], a[-91..-89])
    assert_equal(@cls[98, 99, 100], a[-3..])
    assert_equal(@cls[1, 2, 3], a[..-98])
    assert_equal(@cls[1, 2], a[...-98])

    assert_nil(a[10, -3])
    assert_equal [], a[10..7]

    assert_raise(TypeError) {a['cat']}
  end

  def test_ASET # '[]='
    a = @cls[*(0..99).to_a]
    assert_equal(0, a[0] = 0)
    assert_equal(@cls[0] + @cls[*(1..99).to_a], a)

    a = @cls[*(0..99).to_a]
    assert_equal(0, a[10,10] = 0)
    assert_equal(@cls[*(0..9).to_a] + @cls[0] + @cls[*(20..99).to_a], a)

    a = @cls[*(0..99).to_a]
    assert_equal(0, a[-1] = 0)
    assert_equal(@cls[*(0..98).to_a] + @cls[0], a)

    a = @cls[*(0..99).to_a]
    assert_equal(0, a[-10, 10] = 0)
    assert_equal(@cls[*(0..89).to_a] + @cls[0], a)

    a = @cls[*(0..99).to_a]
    assert_equal(0, a[0,1000] = 0)
    assert_equal(@cls[0] , a)

    a = @cls[*(0..99).to_a]
    assert_equal(0, a[10..19] = 0)
    assert_equal(@cls[*(0..9).to_a] + @cls[0] + @cls[*(20..99).to_a], a)

    b = @cls[*%w( a b c )]
    a = @cls[*(0..99).to_a]
    assert_equal(b, a[0,1] = b)
    assert_equal(b + @cls[*(1..99).to_a], a)

    a = @cls[*(0..99).to_a]
    assert_equal(b, a[10,10] = b)
    assert_equal(@cls[*(0..9).to_a] + b + @cls[*(20..99).to_a], a)

    a = @cls[*(0..99).to_a]
    assert_equal(b, a[-1, 1] = b)
    assert_equal(@cls[*(0..98).to_a] + b, a)

    a = @cls[*(0..99).to_a]
    assert_equal(b, a[-10, 10] = b)
    assert_equal(@cls[*(0..89).to_a] + b, a)

    a = @cls[*(0..99).to_a]
    assert_equal(b, a[0,1000] = b)
    assert_equal(b , a)

    a = @cls[*(0..99).to_a]
    assert_equal(b, a[10..19] = b)
    assert_equal(@cls[*(0..9).to_a] + b + @cls[*(20..99).to_a], a)

    a = @cls[*(0..99).to_a]
    assert_equal(nil, a[0,1] = nil)
    assert_equal(@cls[nil] + @cls[*(1..99).to_a], a)

    a = @cls[*(0..99).to_a]
    assert_equal(nil, a[10,10] = nil)
    assert_equal(@cls[*(0..9).to_a] + @cls[nil] + @cls[*(20..99).to_a], a)

    a = @cls[*(0..99).to_a]
    assert_equal(nil, a[-1, 1] = nil)
    assert_equal(@cls[*(0..98).to_a] + @cls[nil], a)

    a = @cls[*(0..99).to_a]
    assert_equal(nil, a[-10, 10] = nil)
    assert_equal(@cls[*(0..89).to_a] + @cls[nil], a)

    a = @cls[*(0..99).to_a]
    assert_equal(nil, a[0,1000] = nil)
    assert_equal(@cls[nil] , a)

    a = @cls[*(0..99).to_a]
    assert_equal(nil, a[10..19] = nil)
    assert_equal(@cls[*(0..9).to_a] + @cls[nil] + @cls[*(20..99).to_a], a)

    a = @cls[*(0..99).to_a]
    assert_equal(nil, a[10..] = nil)
    assert_equal(@cls[*(0..9).to_a] + @cls[nil], a)

    a = @cls[*(0..99).to_a]
    assert_equal(nil, a[..10] = nil)
    assert_equal(@cls[nil] + @cls[*(11..99).to_a], a)

    a = @cls[*(0..99).to_a]
    assert_equal(nil, a[...10] = nil)
    assert_equal(@cls[nil] + @cls[*(10..99).to_a], a)

    a = @cls[1, 2, 3]
    a[1, 0] = a
    assert_equal([1, 1, 2, 3, 2, 3], a)

    a = @cls[1, 2, 3]
    a[-1, 0] = a
    assert_equal([1, 2, 1, 2, 3, 3], a)

    a = @cls[]
    a[5,0] = [5]
    assert_equal([nil, nil, nil, nil, nil, 5], a)

    a = @cls[1]
    a[1,0] = [2]
    assert_equal([1, 2], a)

    a = @cls[1]
    a[1,1] = [2]
    assert_equal([1, 2], a)
  end

  def test_append
    a = @cls[1, 2, 3]
    assert_equal(@cls[1, 2, 3, 4, 5], a.append(4, 5))
    assert_equal(@cls[1, 2, 3, 4, 5, nil], a.append(nil))

    a.append
    assert_equal @cls[1, 2, 3, 4, 5, nil], a
    a.append 6, 7
    assert_equal @cls[1, 2, 3, 4, 5, nil, 6, 7], a
  end

  def test_assoc
    def (a4 = Object.new).to_ary
      %w( pork porcine )
    end

    a1 = @cls[*%w( cat feline )]
    a2 = @cls[*%w( dog canine )]
    a3 = @cls[*%w( mule asinine )]

    a = @cls[ a1, a2, a3, a4 ]

    assert_equal(a1, a.assoc('cat'))
    assert_equal(a3, a.assoc('mule'))
    assert_equal(%w( pork porcine ), a.assoc("pork"))
    assert_equal(nil, a.assoc('asinine'))
    assert_equal(nil, a.assoc('wombat'))
    assert_equal(nil, a.assoc(1..2))
  end

  def test_at
    a = @cls[*(0..99).to_a]
    assert_equal(0,   a.at(0))
    assert_equal(10,  a.at(10))
    assert_equal(99,  a.at(99))
    assert_equal(nil, a.at(100))
    assert_equal(99,  a.at(-1))
    assert_equal(0,  a.at(-100))
    assert_equal(nil, a.at(-101))
    assert_raise(TypeError) { a.at('cat') }
  end

  def test_clear
    a = @cls[1, 2, 3]
    b = a.clear
    assert_equal(@cls[], a)
    assert_equal(@cls[], b)
    assert_equal(a.__id__, b.__id__)
  end

  def test_clone
    for frozen in [ false, true ]
      a = @cls[*(0..99).to_a]
      a.freeze if frozen
      b = a.clone

      assert_equal(a, b)
      assert_not_equal(a.__id__, b.__id__)
      assert_equal(a.frozen?, b.frozen?)
    end
  end

  def test_collect
    a = @cls[ 1, 'cat', 1..1 ]
    assert_equal([ Integer, String, Range], a.collect {|e| e.class} )
    assert_equal([ 99, 99, 99], a.collect { 99 } )

    assert_equal([], @cls[].collect { 99 })

    assert_kind_of Enumerator, @cls[1, 2, 3].collect

    assert_raise(ArgumentError) {
      assert_equal([[1, 2, 3]], [[1, 2, 3]].collect(&->(a, b, c) {[a, b, c]}))
    }
  end

  # also update map!
  def test_collect!
    a = @cls[ 1, 'cat', 1..1 ]
    assert_equal([ Integer, String, Range], a.collect! {|e| e.class} )
    assert_equal([ Integer, String, Range], a)

    a = @cls[ 1, 'cat', 1..1 ]
    assert_equal([ 99, 99, 99], a.collect! { 99 } )
    assert_equal([ 99, 99, 99], a)

    a = @cls[ ]
    assert_equal([], a.collect! { 99 })
    assert_equal([], a)
  end

  def test_compact
    a = @cls[ 1, nil, nil, 2, 3, nil, 4 ]
    assert_equal(@cls[1, 2, 3, 4], a.compact)

    a = @cls[ nil, 1, nil, 2, 3, nil, 4 ]
    assert_equal(@cls[1, 2, 3, 4], a.compact)

    a = @cls[ 1, nil, nil, 2, 3, nil, 4, nil ]
    assert_equal(@cls[1, 2, 3, 4], a.compact)

    a = @cls[ 1, 2, 3, 4 ]
    assert_equal(@cls[1, 2, 3, 4], a.compact)
  end

  def test_compact!
    a = @cls[ 1, nil, nil, 2, 3, nil, 4 ]
    assert_equal(@cls[1, 2, 3, 4], a.compact!)
    assert_equal(@cls[1, 2, 3, 4], a)

    a = @cls[ nil, 1, nil, 2, 3, nil, 4 ]
    assert_equal(@cls[1, 2, 3, 4], a.compact!)
    assert_equal(@cls[1, 2, 3, 4], a)

    a = @cls[ 1, nil, nil, 2, 3, nil, 4, nil ]
    assert_equal(@cls[1, 2, 3, 4], a.compact!)
    assert_equal(@cls[1, 2, 3, 4], a)

    a = @cls[ 1, 2, 3, 4 ]
    assert_equal(nil, a.compact!)
    assert_equal(@cls[1, 2, 3, 4], a)
  end

  def test_concat
    assert_equal(@cls[1, 2, 3, 4],     @cls[1, 2].concat(@cls[3, 4]))
    assert_equal(@cls[1, 2, 3, 4],     @cls[].concat(@cls[1, 2, 3, 4]))
    assert_equal(@cls[1, 2, 3, 4],     @cls[1].concat(@cls[2, 3], [4]))
    assert_equal(@cls[1, 2, 3, 4],     @cls[1, 2, 3, 4].concat(@cls[]))
    assert_equal(@cls[1, 2, 3, 4],     @cls[1, 2, 3, 4].concat())
    assert_equal(@cls[],               @cls[].concat(@cls[]))
    assert_equal(@cls[@cls[1, 2], @cls[3, 4]], @cls[@cls[1, 2]].concat(@cls[@cls[3, 4]]))

    a = @cls[1, 2, 3]
    a.concat(a)
    assert_equal([1, 2, 3, 1, 2, 3], a)

    b = @cls[4, 5]
    b.concat(b, b)
    assert_equal([4, 5, 4, 5, 4, 5], b)

    assert_raise(TypeError) { @cls[0].concat(:foo) }
    assert_raise(FrozenError) { @cls[0].freeze.concat(:foo) }

    a = @cls[nil]
    def (x = Object.new).to_ary
      ary = Array.new(2)
      ary << [] << [] << :ok
    end
    EnvUtil.under_gc_stress {a.concat(x)}
    GC.start
    assert_equal(:ok, a.last)
  end

  def test_count
    a = @cls[1, 2, 3, 1, 2]
    assert_equal(5, a.count)
    assert_equal(2, a.count(1))
    assert_equal(3, a.count {|x| x % 2 == 1 })
    assert_equal(2, assert_warning(/given block not used/) {a.count(1) {|x| x % 2 == 1 }})
    assert_raise(ArgumentError) { a.count(0, 1) }

    bug8654 = '[ruby-core:56072]'
    assert_in_out_err [], <<-EOS, ["0"], [], bug8654
      a1 = []
      a2 = Array.new(100) { |i| i }
      a2.count do |i|
        p i
        a2.replace(a1) if i == 0
      end
    EOS

    assert_in_out_err [], <<-EOS, ["[]", "0"], [], bug8654
      ARY = Array.new(100) { |i| i }
      class Integer
        alias old_equal ==
        def == other
          ARY.replace([]) if self.equal?(0)
          p ARY
          self.equal?(other)
        end
      end
      p ARY.count(42)
    EOS
  end

  def test_delete
    a = @cls[*('cab'..'cat').to_a]
    assert_equal('cap', a.delete('cap'))
    assert_equal(@cls[*('cab'..'cao').to_a] + @cls[*('caq'..'cat').to_a], a)

    a = @cls[*('cab'..'cat').to_a]
    assert_equal('cab', a.delete('cab'))
    assert_equal(@cls[*('cac'..'cat').to_a], a)

    a = @cls[*('cab'..'cat').to_a]
    assert_equal('cat', a.delete('cat'))
    assert_equal(@cls[*('cab'..'cas').to_a], a)

    a = @cls[*('cab'..'cat').to_a]
    assert_equal(nil, a.delete('cup'))
    assert_equal(@cls[*('cab'..'cat').to_a], a)

    a = @cls[*('cab'..'cat').to_a]
    assert_equal(99, a.delete('cup') { 99 } )
    assert_equal(@cls[*('cab'..'cat').to_a], a)

    o = Object.new
    def o.==(other); true; end
    o2 = Object.new
    def o2.==(other); true; end
    a = @cls[1, o, o2, 2]
    assert_equal(o2, a.delete(42))
    assert_equal([1, 2], a)
  end

  def test_delete_at
    a = @cls[*(1..5).to_a]
    assert_equal(3, a.delete_at(2))
    assert_equal(@cls[1, 2, 4, 5], a)

    a = @cls[*(1..5).to_a]
    assert_equal(4, a.delete_at(-2))
    assert_equal(@cls[1, 2, 3, 5], a)

    a = @cls[*(1..5).to_a]
    assert_equal(nil, a.delete_at(5))
    assert_equal(@cls[1, 2, 3, 4, 5], a)

    a = @cls[*(1..5).to_a]
    assert_equal(nil, a.delete_at(-6))
    assert_equal(@cls[1, 2, 3, 4, 5], a)
  end

  # also reject!
  def test_delete_if
    a = @cls[ 1, 2, 3, 4, 5 ]
    assert_equal(a, a.delete_if { false })
    assert_equal(@cls[1, 2, 3, 4, 5], a)

    a = @cls[ 1, 2, 3, 4, 5 ]
    assert_equal(a, a.delete_if { true })
    assert_equal(@cls[], a)

    a = @cls[ 1, 2, 3, 4, 5 ]
    assert_equal(a, a.delete_if { |i| i > 3 })
    assert_equal(@cls[1, 2, 3], a)

    bug2545 = '[ruby-core:27366]'
    a = @cls[ 5, 6, 7, 8, 9, 10 ]
    assert_equal(9, a.delete_if {|i| break i if i > 8; i < 7})
    assert_equal(@cls[7, 8, 9, 10], a, bug2545)

    assert_raise(FrozenError) do
      a = @cls[1, 2, 3, 42]
      a.delete_if do
        a.freeze
        true
      end
    end
    assert_equal(@cls[1, 2, 3, 42], a)
  end

  def test_dup
    for frozen in [ false, true ]
      a = @cls[*(0..99).to_a]
      a.freeze if frozen
      b = a.dup

      assert_equal(a, b)
      assert_not_equal(a.__id__, b.__id__)
      assert_equal(false, b.frozen?)
    end
  end

  def test_each
    a = @cls[*%w( ant bat cat dog )]
    i = 0
    a.each { |e|
      assert_equal(a[i], e)
      i += 1
    }
    assert_equal(4, i)

    a = @cls[]
    i = 0
    a.each { |e|
      assert(false, "Never get here")
      i += 1
    }
    assert_equal(0, i)

    assert_equal(a, a.each {})
  end

  def test_each_index
    a = @cls[*%w( ant bat cat dog )]
    i = 0
    a.each_index { |ind|
      assert_equal(i, ind)
      i += 1
    }
    assert_equal(4, i)

    a = @cls[]
    i = 0
    a.each_index { |ind|
      assert(false, "Never get here")
      i += 1
    }
    assert_equal(0, i)

    assert_equal(a, a.each_index {})
  end

  def test_empty?
    assert_empty(@cls[])
    assert_not_empty(@cls[1])
  end

  def test_eql?
    assert_send([@cls[], :eql?, @cls[]])
    assert_send([@cls[1], :eql?, @cls[1]])
    assert_send([@cls[1, 1, 2, 2], :eql?, @cls[1, 1, 2, 2]])
    assert_not_send([@cls[1.0, 1.0, 2.0, 2.0], :eql?, @cls[1, 1, 2, 2]])
  end

  def test_fill
    assert_equal(@cls[],   @cls[].fill(99))
    assert_equal(@cls[],   @cls[].fill(99, 0))
    assert_equal(@cls[99], @cls[].fill(99, 0, 1))
    assert_equal(@cls[99], @cls[].fill(99, 0..0))

    assert_equal(@cls[99],   @cls[1].fill(99))
    assert_equal(@cls[99],   @cls[1].fill(99, 0))
    assert_equal(@cls[99],   @cls[1].fill(99, 0, 1))
    assert_equal(@cls[99],   @cls[1].fill(99, 0..0))

    assert_equal(@cls[99, 99], @cls[1, 2].fill(99))
    assert_equal(@cls[99, 99], @cls[1, 2].fill(99, 0))
    assert_equal(@cls[99, 99], @cls[1, 2].fill(99, nil))
    assert_equal(@cls[1,  99], @cls[1, 2].fill(99, 1, nil))
    assert_equal(@cls[99,  2], @cls[1, 2].fill(99, 0, 1))
    assert_equal(@cls[99,  2], @cls[1, 2].fill(99, 0..0))
  end

  def test_first
    assert_equal(3,   @cls[3, 4, 5].first)
    assert_equal(nil, @cls[].first)
  end

  def test_flatten
    a1 = @cls[ 1, 2, 3]
    a2 = @cls[ 5, 6 ]
    a3 = @cls[ 4, a2 ]
    a4 = @cls[ a1, a3 ]
    assert_equal_instance([1, 2, 3, 4, 5, 6], a4.flatten)
    assert_equal_instance(@cls[ a1, a3], a4)

    a5 = @cls[ a1, @cls[], a3 ]
    assert_equal_instance([1, 2, 3, 4, 5, 6], a5.flatten)
    assert_equal_instance([1, 2, 3, 4, [5, 6]], a5.flatten(1))
    assert_equal_instance([], @cls[].flatten)
    assert_equal_instance([],
                 @cls[@cls[@cls[@cls[],@cls[]],@cls[@cls[]],@cls[]],@cls[@cls[@cls[]]]].flatten)
  end

  def test_flatten_wrong_argument
    assert_raise(TypeError, "[ruby-dev:31197]") { [[]].flatten("") }
  end

  def test_flatten_level0
    a8 = @cls[[1, 2], 3]
    a9 = a8.flatten(0)
    assert_equal(a8, a9)
    assert_not_same(a8, a9)
  end

  def test_flatten_splat
    bug10748 = '[ruby-core:67637] [Bug #10748]'
    o = Object.new
    o.singleton_class.class_eval do
      define_method(:to_ary) do
        raise bug10748
      end
    end
    a = @cls[@cls[o]]
    assert_raise_with_message(RuntimeError, bug10748) {a.flatten}
    assert_nothing_raised(RuntimeError, bug10748) {a.flatten(1)}
  end

  def test_flattern_singleton_class
    bug12738 = '[ruby-dev:49781] [Bug #12738]'
    a = [[0]]
    class << a
      def m; end
    end
    assert_raise(NoMethodError, bug12738) { a.flatten.m }
  end

  def test_flatten_recursive
    a = []
    a << a
    assert_raise(ArgumentError) { a.flatten }
    b = [1]; c = [2, b]; b << c
    assert_raise(ArgumentError) { b.flatten }

    assert_equal([1, 2, b], b.flatten(1))
    assert_equal([1, 2, 1, 2, 1, c], b.flatten(4))
  end

  def test_flatten!
    a1 = @cls[ 1, 2, 3]
    a2 = @cls[ 5, 6 ]
    a3 = @cls[ 4, a2 ]
    a4 = @cls[ a1, a3 ]
    assert_equal(@cls[1, 2, 3, 4, 5, 6], a4.flatten!)
    assert_equal(@cls[1, 2, 3, 4, 5, 6], a4)

    a5 = @cls[ a1, @cls[], a3 ]
    assert_equal(@cls[1, 2, 3, 4, 5, 6], a5.flatten!)
    assert_nil(a5.flatten!(0), '[ruby-core:23382]')
    assert_equal(@cls[1, 2, 3, 4, 5, 6], a5)
  end

  def test_flatten_empty!
    assert_nil(@cls[].flatten!)
    assert_equal(@cls[],
                 @cls[@cls[@cls[@cls[],@cls[]],@cls[@cls[]],@cls[]],@cls[@cls[@cls[]]]].flatten!)
  end

  def test_flatten_level0!
    assert_nil(@cls[].flatten!(0), '[ruby-core:23382]')
  end

  def test_flatten_splat!
    bug10748 = '[ruby-core:67637] [Bug #10748]'
    o = Object.new
    o.singleton_class.class_eval do
      define_method(:to_ary) do
        raise bug10748
      end
    end
    a = @cls[@cls[o]]
    assert_raise_with_message(RuntimeError, bug10748) {a.flatten!}
    assert_nothing_raised(RuntimeError, bug10748) {a.flatten!(1)}
  end

  def test_flattern_singleton_class!
    bug12738 = '[ruby-dev:49781] [Bug #12738]'
    a = [[0]]
    class << a
      def m; end
    end
    assert_nothing_raised(NameError, bug12738) { a.flatten!.m }
  end

  def test_flatten_with_callcc
    need_continuation
    o = Object.new
    def o.to_ary() callcc {|k| @cont = k; [1,2,3]} end
    begin
      assert_equal([10, 20, 1, 2, 3, 30, 1, 2, 3, 40], [10, 20, o, 30, o, 40].flatten)
    rescue => e
    else
      o.instance_eval {@cont}.call
    end
    assert_instance_of(RuntimeError, e, '[ruby-dev:34798]')
    assert_match(/reentered/, e.message, '[ruby-dev:34798]')
  end

  def test_flatten_respond_to_missing
    bug11465 = '[ruby-core:70460] [Bug #11465]'

    obj = Class.new do
      def respond_to_missing?(method, stuff)
        return false if method == :to_ary
        super
      end

      def method_missing(*args)
        super
      end
    end.new

    ex = nil
    trace = TracePoint.new(:raise) do |tp|
      ex = tp.raised_exception
    end
    trace.enable {[obj].flatten}
    assert_nil(ex, bug11465)
  end

  def test_permutation_with_callcc
    need_continuation
    n = 1000
    cont = nil
    ary = [1,2,3]
    begin
      ary.permutation {
        callcc {|k| cont = k} unless cont
      }
    rescue => e
    end
    n -= 1
    cont.call if 0 < n
    assert_instance_of(RuntimeError, e)
    assert_match(/reentered/, e.message)
  end

  def test_product_with_callcc
    need_continuation
    n = 1000
    cont = nil
    ary = [1,2,3]
    begin
      ary.product {
        callcc {|k| cont = k} unless cont
      }
    rescue => e
    end
    n -= 1
    cont.call if 0 < n
    assert_instance_of(RuntimeError, e)
    assert_match(/reentered/, e.message)
  end

  def test_combination_with_callcc
    need_continuation
    n = 1000
    cont = nil
    ary = [1,2,3]
    begin
      ary.combination(2) {
        callcc {|k| cont = k} unless cont
      }
    rescue => e
    end
    n -= 1
    cont.call if 0 < n
    assert_instance_of(RuntimeError, e)
    assert_match(/reentered/, e.message)
  end

  def test_repeated_permutation_with_callcc
    need_continuation
    n = 1000
    cont = nil
    ary = [1,2,3]
    begin
      ary.repeated_permutation(2) {
        callcc {|k| cont = k} unless cont
      }
    rescue => e
    end
    n -= 1
    cont.call if 0 < n
    assert_instance_of(RuntimeError, e)
    assert_match(/reentered/, e.message)
  end

  def test_repeated_combination_with_callcc
    need_continuation
    n = 1000
    cont = nil
    ary = [1,2,3]
    begin
      ary.repeated_combination(2) {
        callcc {|k| cont = k} unless cont
      }
    rescue => e
    end
    n -= 1
    cont.call if 0 < n
    assert_instance_of(RuntimeError, e)
    assert_match(/reentered/, e.message)
  end

  def test_hash
    a1 = @cls[ 'cat', 'dog' ]
    a2 = @cls[ 'cat', 'dog' ]
    a3 = @cls[ 'dog', 'cat' ]
    assert_equal(a1.hash, a2.hash)
    assert_not_equal(a1.hash, a3.hash)
    bug9231 = '[ruby-core:58993] [Bug #9231]'
    assert_not_equal(false.hash, @cls[].hash, bug9231)
  end

  def test_include?
    a = @cls[ 'cat', 99, /a/, @cls[ 1, 2, 3] ]
    assert_include(a, 'cat')
    assert_include(a, 99)
    assert_include(a, /a/)
    assert_include(a, [1,2,3])
    assert_not_include(a, 'ca')
    assert_not_include(a, [1,2])
  end

  def test_intersect?
    a = @cls[ 1, 2, 3]
    assert_send([a, :intersect?, [3]])
    assert_not_send([a, :intersect?, [4]])
    assert_not_send([a, :intersect?, []])
  end

  def test_intersect_big_array
    assert_send([@cls[ 1, 4, 5 ]*64, :intersect?, @cls[ 1, 2, 3 ]*64])
    assert_not_send([@cls[ 1, 2, 3 ]*64, :intersect?, @cls[ 4, 5, 6 ]*64])
    assert_not_send([@cls[], :intersect?, @cls[ 1, 2, 3 ]*64])
  end

  def test_index
    a = @cls[ 'cat', 99, /a/, 99, @cls[ 1, 2, 3] ]
    assert_equal(0, a.index('cat'))
    assert_equal(1, a.index(99))
    assert_equal(4, a.index([1,2,3]))
    assert_nil(a.index('ca'))
    assert_nil(a.index([1,2]))

    assert_equal(1, assert_warn(/given block not used/) {a.index(99) {|x| x == 'cat' }})
  end

  def test_values_at
    a = @cls[*('a'..'j').to_a]
    assert_equal(@cls['a', 'c', 'e'], a.values_at(0, 2, 4))
    assert_equal(@cls['j', 'h', 'f'], a.values_at(-1, -3, -5))
    assert_equal(@cls['h', nil, 'a'], a.values_at(-3, 99, 0))
  end

  def test_join
    assert_deprecated_warning {$, = ""}
    a = @cls[]
    assert_equal("", assert_deprecated_warn(/non-nil value/) {a.join})
    assert_equal("", a.join(','))
    assert_equal(Encoding::US_ASCII, assert_deprecated_warn(/non-nil value/) {a.join}.encoding)

    assert_deprecated_warning {$, = ""}
    a = @cls[1, 2]
    assert_equal("12", assert_deprecated_warn(/non-nil value/) {a.join})
    assert_equal("12", assert_deprecated_warn(/non-nil value/) {a.join(nil)})
    assert_equal("1,2", a.join(','))

    assert_deprecated_warning {$, = ""}
    a = @cls[1, 2, 3]
    assert_equal("123", assert_deprecated_warn(/non-nil value/) {a.join})
    assert_equal("123", assert_deprecated_warn(/non-nil value/) {a.join(nil)})
    assert_equal("1,2,3", a.join(','))

    assert_deprecated_warning {$, = ":"}
    a = @cls[1, 2, 3]
    assert_equal("1:2:3", assert_deprecated_warn(/non-nil value/) {a.join})
    assert_equal("1:2:3", assert_deprecated_warn(/non-nil value/) {a.join(nil)})
    assert_equal("1,2,3", a.join(','))

    assert_deprecated_warning {$, = ""}

    e = ''.force_encoding('EUC-JP')
    u = ''.force_encoding('UTF-8')
    assert_equal(Encoding::US_ASCII, assert_deprecated_warn(/non-nil value/) {[[]].join}.encoding)
    assert_equal(Encoding::US_ASCII, assert_deprecated_warn(/non-nil value/) {[1, [u]].join}.encoding)
    assert_equal(Encoding::UTF_8, assert_deprecated_warn(/non-nil value/) {[u, [e]].join}.encoding)
    assert_equal(Encoding::UTF_8, assert_deprecated_warn(/non-nil value/) {[u, [1]].join}.encoding)
    assert_equal(Encoding::UTF_8, assert_deprecated_warn(/non-nil value/) {[Struct.new(:to_str).new(u)].join}.encoding)
    bug5379 = '[ruby-core:39776]'
    assert_equal(Encoding::US_ASCII, assert_deprecated_warn(/non-nil value/) {[[], u, nil].join}.encoding, bug5379)
    assert_equal(Encoding::UTF_8, assert_deprecated_warn(/non-nil value/) {[[], "\u3042", nil].join}.encoding, bug5379)
  ensure
    $, = nil
  end

  def test_last
    assert_equal(nil, @cls[].last)
    assert_equal(1, @cls[1].last)
    assert_equal(99, @cls[*(3..99).to_a].last)
  end

  def test_length
    assert_equal(0, @cls[].length)
    assert_equal(1, @cls[1].length)
    assert_equal(2, @cls[1, nil].length)
    assert_equal(2, @cls[nil, 1].length)
    assert_equal(234, @cls[*(0..233).to_a].length)
  end

  # also update collect!
  def test_map!
    a = @cls[ 1, 'cat', 1..1 ]
    assert_equal(@cls[ Integer, String, Range], a.map! {|e| e.class} )
    assert_equal(@cls[ Integer, String, Range], a)

    a = @cls[ 1, 'cat', 1..1 ]
    assert_equal(@cls[ 99, 99, 99], a.map! { 99 } )
    assert_equal(@cls[ 99, 99, 99], a)

    a = @cls[ ]
    assert_equal(@cls[], a.map! { 99 })
    assert_equal(@cls[], a)
  end

  def test_pack
    a = @cls[*%w( cat wombat x yy)]
    assert_equal("catwomx  yy ", a.pack("A3A3A3A3"))
    assert_equal("cat", a.pack("A*"))
    assert_equal("cwx  yy ", a.pack("A3@1A3@2A3A3"))
    assert_equal("catwomx\000\000yy\000", a.pack("a3a3a3a3"))
    assert_equal("cat", a.pack("a*"))
    assert_equal("ca", a.pack("a2"))
    assert_equal("cat\000\000", a.pack("a5"))

    assert_equal("\x61",     @cls["01100001"].pack("B8"))
    assert_equal("\x61",     @cls["01100001"].pack("B*"))
    assert_equal("\x61",     @cls["0110000100110111"].pack("B8"))
    assert_equal("\x61\x37", @cls["0110000100110111"].pack("B16"))
    assert_equal("\x61\x37", @cls["01100001", "00110111"].pack("B8B8"))
    assert_equal("\x60",     @cls["01100001"].pack("B4"))
    assert_equal("\x40",     @cls["01100001"].pack("B2"))

    assert_equal("\x86",     @cls["01100001"].pack("b8"))
    assert_equal("\x86",     @cls["01100001"].pack("b*"))
    assert_equal("\x86",     @cls["0110000100110111"].pack("b8"))
    assert_equal("\x86\xec", @cls["0110000100110111"].pack("b16"))
    assert_equal("\x86\xec", @cls["01100001", "00110111"].pack("b8b8"))
    assert_equal("\x06",     @cls["01100001"].pack("b4"))
    assert_equal("\x02",     @cls["01100001"].pack("b2"))

    assert_equal("ABC",      @cls[ 65, 66, 67 ].pack("C3"))
    assert_equal("\377BC",   @cls[ -1, 66, 67 ].pack("C*"))
    assert_equal("ABC",      @cls[ 65, 66, 67 ].pack("c3"))
    assert_equal("\377BC",   @cls[ -1, 66, 67 ].pack("c*"))


    assert_equal("AB\n\x10",  @cls["4142", "0a", "12"].pack("H4H2H1"))
    assert_equal("AB\n\x02",  @cls["1424", "a0", "21"].pack("h4h2h1"))

    assert_equal("abc=02def=\ncat=\n=01=\n",
                 @cls["abc\002def", "cat", "\001"].pack("M9M3M4"))

    assert_equal("aGVsbG8K\n",  @cls["hello\n"].pack("m"))
    assert_equal(",:&5L;&\\*:&5L;&\\*\n",  @cls["hello\nhello\n"].pack("u"))

    assert_equal("\u{a9 42 2260}", @cls[0xa9, 0x42, 0x2260].pack("U*"))


    format = "c2x5CCxsdils_l_a6";
    # Need the expression in here to force ary[5] to be numeric.  This avoids
    # test2 failing because ary2 goes str->numeric->str and ary does not.
    ary = [1, -100, 127, 128, 32767, 987.654321098/100.0,
      12345, 123456, -32767, -123456, "abcdef"]
    x    = ary.pack(format)
    ary2 = x.unpack(format)

    assert_equal(ary.length, ary2.length)
    assert_equal(ary.join(':'), ary2.join(':'))
    assert_not_nil(x =~ /def/)

=begin
    skipping "Not tested:
        D,d & double-precision float, native format\\
        E & double-precision float, little-endian byte order\\
        e & single-precision float, little-endian byte order\\
        F,f & single-precision float, native format\\
        G & double-precision float, network (big-endian) byte order\\
        g & single-precision float, network (big-endian) byte order\\
        I & unsigned integer\\
        i & integer\\
        L & unsigned long\\
        l & long\\

        N & long, network (big-endian) byte order\\
        n & short, network (big-endian) byte-order\\
        P & pointer to a structure (fixed-length string)\\
        p & pointer to a null-terminated string\\
        S & unsigned short\\
        s & short\\
        V & long, little-endian byte order\\
        v & short, little-endian byte order\\
        X & back up a byte\\
        x & null byte\\
        Z & ASCII string (null padded, count is width)\\
"
=end
  end

  def test_pack_with_buffer
    n = [ 65, 66, 67 ]
    str = "a" * 100
    assert_equal("aaaABC", n.pack("@3ccc", buffer: str.dup), "[Bug #19116]")
  end

  def test_pop
    a = @cls[ 'cat', 'dog' ]
    assert_equal('dog', a.pop)
    assert_equal(@cls['cat'], a)
    assert_equal('cat', a.pop)
    assert_equal(@cls[], a)
    assert_nil(a.pop)
    assert_equal(@cls[], a)
  end

  def test_prepend
    a = @cls[]
    assert_equal(@cls['cat'], a.prepend('cat'))
    assert_equal(@cls['dog', 'cat'], a.prepend('dog'))
    assert_equal(@cls[nil, 'dog', 'cat'], a.prepend(nil))
    assert_equal(@cls[@cls[1,2], nil, 'dog', 'cat'], a.prepend(@cls[1, 2]))
  end

  def test_push
    a = @cls[1, 2, 3]
    assert_equal(@cls[1, 2, 3, 4, 5], a.push(4, 5))
    assert_equal(@cls[1, 2, 3, 4, 5, nil], a.push(nil))
    a.push
    assert_equal @cls[1, 2, 3, 4, 5, nil], a
    a.push 6, 7
    assert_equal @cls[1, 2, 3, 4, 5, nil, 6, 7], a
  end

  def test_rassoc
    def (a4 = Object.new).to_ary
      %w( pork porcine )
    end
    a1 = @cls[*%w( cat  feline )]
    a2 = @cls[*%w( dog  canine )]
    a3 = @cls[*%w( mule asinine )]
    a  = @cls[ a1, a2, a3, a4 ]

    assert_equal(a1,  a.rassoc('feline'))
    assert_equal(a3,  a.rassoc('asinine'))
    assert_equal(%w( pork porcine ), a.rassoc("porcine"))
    assert_equal(nil, a.rassoc('dog'))
    assert_equal(nil, a.rassoc('mule'))
    assert_equal(nil, a.rassoc(1..2))
  end

  # also delete_if
  def test_reject!
    a = @cls[ 1, 2, 3, 4, 5 ]
    assert_equal(nil, a.reject! { false })
    assert_equal(@cls[1, 2, 3, 4, 5], a)

    a = @cls[ 1, 2, 3, 4, 5 ]
    assert_equal(a, a.reject! { true })
    assert_equal(@cls[], a)

    a = @cls[ 1, 2, 3, 4, 5 ]
    assert_equal(a, a.reject! { |i| i > 3 })
    assert_equal(@cls[1, 2, 3], a)

    bug2545 = '[ruby-core:27366]'
    a = @cls[ 5, 6, 7, 8, 9, 10 ]
    assert_equal(9, a.reject! {|i| break i if i > 8; i < 7})
    assert_equal(@cls[7, 8, 9, 10], a, bug2545)

    assert_raise(FrozenError) do
      a = @cls[1, 2, 3, 42]
      a.reject! do
        a.freeze
        true
      end
    end
    assert_equal(@cls[1, 2, 3, 42], a)
  end

  def test_shared_array_reject!
    c = []
    b = [1, 2, 3, 4]
    3.times do
      a = b.dup
      c << a.dup

      begin
        a.reject! do |x|
          case x
          when 2 then true
          when 3 then raise StandardError, 'Oops'
          else false
          end
        end
      rescue StandardError
      end

      c << a.dup
    end

    bug90781 = '[ruby-core:90781]'
    assert_equal [[1, 2, 3, 4],
                  [1, 3, 4],
                  [1, 2, 3, 4],
                  [1, 3, 4],
                  [1, 2, 3, 4],
                  [1, 3, 4]], c, bug90781
  end

  def test_iseq_shared_array_reject!
    c = []
    3.times do
      a = [1, 2, 3, 4]
      c << a.dup

      begin
        a.reject! do |x|
          case x
          when 2 then true
          when 3 then raise StandardError, 'Oops'
          else false
          end
        end
      rescue StandardError
      end

      c << a.dup
    end

    bug90781 = '[ruby-core:90781]'
    assert_equal [[1, 2, 3, 4],
                  [1, 3, 4],
                  [1, 2, 3, 4],
                  [1, 3, 4],
                  [1, 2, 3, 4],
                  [1, 3, 4]], c, bug90781
  end

  def test_replace
    a = @cls[ 1, 2, 3]
    a_id = a.__id__
    assert_equal(@cls[4, 5, 6], a.replace(@cls[4, 5, 6]))
    assert_equal(@cls[4, 5, 6], a)
    assert_equal(a_id, a.__id__)
    assert_equal(@cls[], a.replace(@cls[]))

    fa = a.dup.freeze
    assert_nothing_raised(RuntimeError) { a.replace(a) }
    assert_raise(FrozenError) { fa.replace(fa) }
    assert_raise(ArgumentError) { fa.replace() }
    assert_raise(TypeError) { a.replace(42) }
    assert_raise(FrozenError) { fa.replace(42) }
  end

  def test_replace_wb_variable_width_alloc
    small_embed = []
    4.times { GC.start } # age small_embed
    large_embed = [1, 2, 3, 4, 5, Array.new] # new young object
    small_embed.replace(large_embed) # adds old to young reference
    GC.verify_internal_consistency
  end

  def test_reverse
    a = @cls[*%w( dog cat bee ant )]
    assert_equal(@cls[*%w(ant bee cat dog)], a.reverse)
    assert_equal(@cls[*%w(dog cat bee ant)], a)
    assert_equal(@cls[], @cls[].reverse)
  end

  def test_reverse!
    a = @cls[*%w( dog cat bee ant )]
    assert_equal(@cls[*%w(ant bee cat dog)], a.reverse!)
    assert_equal(@cls[*%w(ant bee cat dog)], a)
    assert_equal @cls[], @cls[].reverse!
  end

  def test_reverse_each
    a = @cls[*%w( dog cat bee ant )]
    i = a.length
    a.reverse_each { |e|
      i -= 1
      assert_equal(a[i], e)
    }
    assert_equal(0, i)

    a = @cls[]
    i = 0
    a.reverse_each { |e|
      i += 1
      assert(false, "Never get here")
    }
    assert_equal(0, i)
  end

  def test_rindex
    a = @cls[ 'cat', 99, /a/, 99, [ 1, 2, 3] ]
    assert_equal(0, a.rindex('cat'))
    assert_equal(3, a.rindex(99))
    assert_equal(4, a.rindex([1,2,3]))
    assert_nil(a.rindex('ca'))
    assert_nil(a.rindex([1,2]))

    assert_equal(3, assert_warning(/given block not used/) {a.rindex(99) {|x| x == [1,2,3] }})

    bug15951 = "[Bug #15951]"
    o2 = Object.new
    def o2.==(other)
      other.replace([]) if Array === other
      false
    end
    a = Array.new(10)
    a.fill(o2)
    assert_nil(a.rindex(a), bug15951)
  end

  def test_shift
    a = @cls[ 'cat', 'dog' ]
    assert_equal('cat', a.shift)
    assert_equal(@cls['dog'], a)
    assert_equal('dog', a.shift)
    assert_equal(@cls[], a)
    assert_nil(a.shift)
    assert_equal(@cls[], a)
  end

  def test_size
    assert_equal(0,   @cls[].size)
    assert_equal(1,   @cls[1].size)
    assert_equal(100, @cls[*(0..99).to_a].size)
  end

  def test_slice
    a = @cls[*(1..100).to_a]

    assert_equal(1, a.slice(0))
    assert_equal(100, a.slice(99))
    assert_nil(a.slice(100))
    assert_equal(100, a.slice(-1))
    assert_equal(99,  a.slice(-2))
    assert_equal(1,   a.slice(-100))
    assert_nil(a.slice(-101))

    assert_equal_instance([1],   a.slice(0,1))
    assert_equal_instance([100], a.slice(99,1))
    assert_equal_instance([],    a.slice(100,1))
    assert_equal_instance([100], a.slice(99,100))
    assert_equal_instance([100], a.slice(-1,1))
    assert_equal_instance([99],  a.slice(-2,1))

    assert_equal_instance([10, 11, 12], a.slice(9, 3))
    assert_equal_instance([10, 11, 12], a.slice(-91, 3))

    assert_nil(a.slice(-101, 2))

    assert_equal_instance([1],   a.slice(0..0))
    assert_equal_instance([100], a.slice(99..99))
    assert_equal_instance([],    a.slice(100..100))
    assert_equal_instance([100], a.slice(99..200))
    assert_equal_instance([100], a.slice(-1..-1))
    assert_equal_instance([99],  a.slice(-2..-2))

    assert_equal_instance([10, 11, 12], a.slice(9..11))
    assert_equal_instance([98, 99, 100], a.slice(97..))
    assert_equal_instance([10, 11, 12], a.slice(-91..-89))
    assert_equal_instance([10, 11, 12], a.slice(-91..-89))

    assert_equal_instance([5, 8, 11], a.slice((4..12)%3))
    assert_equal_instance([95, 97, 99], a.slice((94..)%2))

    #        [0] [1] [2] [3] [4] [5] [6] [7]
    # ary = [ 1   2   3   4   5   6   7   8  ... ]
    #        (0)         (1)         (2)           <- (..7) % 3
    #            (2)         (1)         (0)       <- (7..) % -3
    assert_equal_instance([1, 4, 7], a.slice((..7)%3))
    assert_equal_instance([8, 5, 2], a.slice((7..)% -3))

    #             [-98] [-97] [-96] [-95] [-94] [-93] [-92] [-91] [-90]
    # ary = [ ...   3     4     5     6     7     8     9     10    11  ... ]
    #              (0)               (1)               (2)                    <- (-98..-90) % 3
    #                          (2)               (1)               (0)        <- (-90..-98) % -3
    assert_equal_instance([3, 6, 9], a.slice((-98..-90)%3))
    assert_equal_instance([11, 8, 5], a.slice((-90..-98)% -3))

    #             [ 48] [ 49] [ 50] [ 51] [ 52] [ 53]
    #             [-52] [-51] [-50] [-49] [-48] [-47]
    # ary = [ ...   49    50    51    52    53    54  ... ]
    #              (0)         (1)         (2)              <- (48..-47) % 2
    #                    (2)         (1)          (0)       <- (-47..48) % -2
    assert_equal_instance([49, 51, 53], a.slice((48..-47)%2))
    assert_equal_instance([54, 52, 50], a.slice((-47..48)% -2))

    idx = ((3..90) % 2).to_a
    assert_equal_instance(a.values_at(*idx), a.slice((3..90)%2))
    idx = 90.step(3, -2).to_a
    assert_equal_instance(a.values_at(*idx), a.slice((90 .. 3)% -2))

    a = [0, 1, 2, 3, 4, 5]
    assert_equal([2, 1, 0], a.slice((2..).step(-1)))
    assert_equal([2, 0], a.slice((2..).step(-2)))
    assert_equal([2], a.slice((2..).step(-3)))
    assert_equal([2], a.slice((2..).step(-4)))

    assert_equal([3, 2, 1, 0], a.slice((-3..).step(-1)))
    assert_equal([3, 1], a.slice((-3..).step(-2)))
    assert_equal([3, 0], a.slice((-3..).step(-3)))
    assert_equal([3], a.slice((-3..).step(-4)))
    assert_equal([3], a.slice((-3..).step(-5)))

    assert_equal([5, 4, 3, 2, 1, 0], a.slice((..0).step(-1)))
    assert_equal([5, 3, 1], a.slice((..0).step(-2)))
    assert_equal([5, 2], a.slice((..0).step(-3)))
    assert_equal([5, 1], a.slice((..0).step(-4)))
    assert_equal([5, 0], a.slice((..0).step(-5)))
    assert_equal([5], a.slice((..0).step(-6)))
    assert_equal([5], a.slice((..0).step(-7)))

    assert_equal([5, 4, 3, 2, 1], a.slice((...0).step(-1)))
    assert_equal([5, 3, 1], a.slice((...0).step(-2)))
    assert_equal([5, 2], a.slice((...0).step(-3)))
    assert_equal([5, 1], a.slice((...0).step(-4)))
    assert_equal([5], a.slice((...0).step(-5)))
    assert_equal([5], a.slice((...0).step(-6)))

    assert_equal([5, 4, 3, 2], a.slice((...1).step(-1)))
    assert_equal([5, 3], a.slice((...1).step(-2)))
    assert_equal([5, 2], a.slice((...1).step(-3)))
    assert_equal([5], a.slice((...1).step(-4)))
    assert_equal([5], a.slice((...1).step(-5)))

    assert_equal([5, 4, 3, 2, 1], a.slice((..-5).step(-1)))
    assert_equal([5, 3, 1], a.slice((..-5).step(-2)))
    assert_equal([5, 2], a.slice((..-5).step(-3)))
    assert_equal([5, 1], a.slice((..-5).step(-4)))
    assert_equal([5], a.slice((..-5).step(-5)))
    assert_equal([5], a.slice((..-5).step(-6)))

    assert_equal([5, 4, 3, 2], a.slice((...-5).step(-1)))
    assert_equal([5, 3], a.slice((...-5).step(-2)))
    assert_equal([5, 2], a.slice((...-5).step(-3)))
    assert_equal([5], a.slice((...-5).step(-4)))
    assert_equal([5], a.slice((...-5).step(-5)))

    assert_equal([4, 3, 2, 1], a.slice((4..1).step(-1)))
    assert_equal([4, 2], a.slice((4..1).step(-2)))
    assert_equal([4, 1], a.slice((4..1).step(-3)))
    assert_equal([4], a.slice((4..1).step(-4)))
    assert_equal([4], a.slice((4..1).step(-5)))

    assert_equal([4, 3, 2], a.slice((4...1).step(-1)))
    assert_equal([4, 2], a.slice((4...1).step(-2)))
    assert_equal([4], a.slice((4...1).step(-3)))
    assert_equal([4], a.slice((4...1).step(-4)))

    assert_equal([4, 3, 2, 1], a.slice((-2..1).step(-1)))
    assert_equal([4, 2], a.slice((-2..1).step(-2)))
    assert_equal([4, 1], a.slice((-2..1).step(-3)))
    assert_equal([4], a.slice((-2..1).step(-4)))
    assert_equal([4], a.slice((-2..1).step(-5)))

    assert_equal([4, 3, 2], a.slice((-2...1).step(-1)))
    assert_equal([4, 2], a.slice((-2...1).step(-2)))
    assert_equal([4], a.slice((-2...1).step(-3)))
    assert_equal([4], a.slice((-2...1).step(-4)))

    assert_equal([4, 3, 2, 1], a.slice((4..-5).step(-1)))
    assert_equal([4, 2], a.slice((4..-5).step(-2)))
    assert_equal([4, 1], a.slice((4..-5).step(-3)))
    assert_equal([4], a.slice((4..-5).step(-4)))
    assert_equal([4], a.slice((4..-5).step(-5)))

    assert_equal([4, 3, 2], a.slice((4...-5).step(-1)))
    assert_equal([4, 2], a.slice((4...-5).step(-2)))
    assert_equal([4], a.slice((4...-5).step(-3)))
    assert_equal([4], a.slice((4...-5).step(-4)))

    assert_equal([4, 3, 2, 1], a.slice((-2..-5).step(-1)))
    assert_equal([4, 2], a.slice((-2..-5).step(-2)))
    assert_equal([4, 1], a.slice((-2..-5).step(-3)))
    assert_equal([4], a.slice((-2..-5).step(-4)))
    assert_equal([4], a.slice((-2..-5).step(-5)))

    assert_equal([4, 3, 2], a.slice((-2...-5).step(-1)))
    assert_equal([4, 2], a.slice((-2...-5).step(-2)))
    assert_equal([4], a.slice((-2...-5).step(-3)))
    assert_equal([4], a.slice((-2...-5).step(-4)))
  end

  def test_slice_out_of_range
    a = @cls[*(1..100).to_a]

    assert_nil(a.slice(-101..-1))
    assert_nil(a.slice(-101..))

    assert_raise_with_message(RangeError, "((-101..-1).%(2)) out of range") { a.slice((-101..-1)%2) }
    assert_raise_with_message(RangeError, "((-101..).%(2)) out of range") { a.slice((-101..)%2) }

    assert_nil(a.slice(10, -3))
    assert_equal @cls[], a.slice(10..7)

    assert_equal([100], a.slice(-1, 1_000_000_000))
  end

  def test_slice_gc_compact_stress
    omit "compaction doesn't work well on s390x" if RUBY_PLATFORM =~ /s390x/ # https://github.com/ruby/ruby/pull/5077
    EnvUtil.under_gc_compact_stress { assert_equal([1, 2, 3, 4, 5], (0..10).to_a[1, 5]) }
    EnvUtil.under_gc_compact_stress do
      a = [0, 1, 2, 3, 4, 5]
      assert_equal([2, 1, 0], a.slice((2..).step(-1)))
    end
  end

  def test_slice!
    a = @cls[1, 2, 3, 4, 5]
    assert_equal(3, a.slice!(2))
    assert_equal(@cls[1, 2, 4, 5], a)

    a = @cls[1, 2, 3, 4, 5]
    assert_equal(4, a.slice!(-2))
    assert_equal(@cls[1, 2, 3, 5], a)

    a = @cls[1, 2, 3, 4, 5]
    s = a.slice!(2,2)
    assert_equal_instance([3,4], s)
    assert_equal(@cls[1, 2, 5], a)

    a = @cls[1, 2, 3, 4, 5]
    s = a.slice!(-2,2)
    assert_equal_instance([4,5], s)
    assert_equal(@cls[1, 2, 3], a)

    a = @cls[1, 2, 3, 4, 5]
    s = a.slice!(2..3)
    assert_equal_instance([3,4], s)
    assert_equal(@cls[1, 2, 5], a)

    a = @cls[1, 2, 3, 4, 5]
    assert_equal(nil, a.slice!(20))
    assert_equal(@cls[1, 2, 3, 4, 5], a)

    a = @cls[1, 2, 3, 4, 5]
    assert_equal(nil, a.slice!(-6))
    assert_equal(@cls[1, 2, 3, 4, 5], a)

    a = @cls[1, 2, 3, 4, 5]
    assert_equal(nil, a.slice!(-6..4))
    assert_equal(@cls[1, 2, 3, 4, 5], a)

    a = @cls[1, 2, 3, 4, 5]
    assert_equal(nil, a.slice!(-6,2))
    assert_equal(@cls[1, 2, 3, 4, 5], a)

    assert_equal("[2, 3]", [1,2,3].slice!(1,10000).inspect, "moved from btest/knownbug")

    assert_raise(ArgumentError) { @cls[1].slice! }
    assert_raise(ArgumentError) { @cls[1].slice!(0, 0, 0) }
  end

  def test_slice_out_of_range!
    a = @cls[*(1..100).to_a]

    assert_nil(a.clone.slice!(-101..-1))
    assert_nil(a.clone.slice!(-101..))

    # assert_raise_with_message(RangeError, "((-101..-1).%(2)) out of range") { a.clone.slice!((-101..-1)%2) }
    # assert_raise_with_message(RangeError, "((-101..).%(2)) out of range") { a.clone.slice!((-101..)%2) }

    assert_nil(a.clone.slice!(10, -3))
    assert_equal @cls[], a.clone.slice!(10..7)

    assert_equal([100], a.clone.slice!(-1, 1_000_000_000))
  end

  def test_sort
    a = @cls[ 4, 1, 2, 3 ]
    assert_equal(@cls[1, 2, 3, 4], a.sort)
    assert_equal(@cls[4, 1, 2, 3], a)

    assert_equal(@cls[4, 3, 2, 1], a.sort { |x, y| y <=> x} )
    assert_equal(@cls[4, 1, 2, 3], a)

    assert_equal(@cls[1, 2, 3, 4], a.sort { |x, y| (x - y) * (2**100) })

    a.fill(1)
    assert_equal(@cls[1, 1, 1, 1], a.sort)

    assert_equal(@cls[], @cls[].sort)
  end

  def test_sort!
    a = @cls[ 4, 1, 2, 3 ]
    assert_equal(@cls[1, 2, 3, 4], a.sort!)
    assert_equal(@cls[1, 2, 3, 4], a)

    assert_equal(@cls[4, 3, 2, 1], a.sort! { |x, y| y <=> x} )
    assert_equal(@cls[4, 3, 2, 1], a)

    a.fill(1)
    assert_equal(@cls[1, 1, 1, 1], a.sort!)

    assert_equal(@cls[1], @cls[1].sort!)
    assert_equal(@cls[], @cls[].sort!)

    a = @cls[4, 3, 2, 1]
    a.sort! {|m, n| a.replace([9, 8, 7, 6]); m <=> n }
    assert_equal([1, 2, 3, 4], a)

    a = @cls[4, 3, 2, 1]
    a.sort! {|m, n| a.replace([9, 8, 7]); m <=> n }
    assert_equal([1, 2, 3, 4], a)
  end

  def test_freeze_inside_sort!
    array = [1, 2, 3, 4, 5]
    frozen_array = nil
    assert_raise(FrozenError) do
      count = 0
      array.sort! do |a, b|
        array.freeze if (count += 1) == 6
        frozen_array ||= array.map.to_a if array.frozen?
        b <=> a
      end
    end
    assert_equal(frozen_array, array)

    object = Object.new
    array = [1, 2, 3, 4, 5]
    object.define_singleton_method(:>){|_| array.freeze; true}
    assert_raise(FrozenError) do
      array.sort! do |a, b|
        object
      end
    end

    object = Object.new
    array = [object, object]
    object.define_singleton_method(:>){|_| array.freeze; true}
    object.define_singleton_method(:<=>){|o| object}
    assert_raise(FrozenError) do
      array.sort!
    end
  end

  def test_sort_with_callcc
    need_continuation
    n = 1000
    cont = nil
    ary = (1..100).to_a
    begin
      ary.sort! {|a,b|
        callcc {|k| cont = k} unless cont
        assert_equal(100, ary.size, '[ruby-core:16679]')
        a <=> b
      }
    rescue => e
    end
    n -= 1
    cont.call if 0 < n
    assert_instance_of(RuntimeError, e, '[ruby-core:16679]')
    assert_match(/reentered/, e.message, '[ruby-core:16679]')
  end

  def test_sort_with_replace
    bug = '[ruby-core:34732]'
    assert_separately([], "#{<<~"begin;"}\n#{<<~'end;'}", timeout: 30)
    bug = "#{bug}"
    begin;
      xary = (1..100).to_a
      100.times do
        ary = (1..100).to_a
        ary.sort! {|a,b| ary.replace(xary); a <=> b}
        GC.start
        assert_equal(xary, ary, '[ruby-dev:34732]')
      end
      assert_nothing_raised(SystemStackError, bug) do
        assert_equal(:ok, Array.new(100_000, nil).permutation {break :ok})
      end
    end;
  end

  def test_sort_bang_with_freeze
    ary = []
    o1 = Object.new
    o1.singleton_class.class_eval {
      define_method(:<=>) {|v|
        ary.freeze
        1
      }
    }
    o2 = o1.clone
    ary << o1 << o2
    orig = ary.dup
    assert_raise(FrozenError, "frozen during comparison") {ary.sort!}
    assert_equal(orig, ary, "must not be modified once frozen")
  end

  def test_short_heap_array_sort_bang_memory_leak
    bug11332 = '[ruby-dev:49166] [Bug #11332]'
    assert_no_memory_leak([], <<-PREP, <<-TEST, bug11332, limit: 1.3, timeout: 60)
      def t; ary = [*1..5]; ary.pop(2); ary.sort!; end
      1.times {t}
    PREP
      500000.times {t}
    TEST
  end

  def test_sort_uncomparable
    assert_raise(ArgumentError) {[1, Float::NAN].sort}
    assert_raise(ArgumentError) {[1.0, Float::NAN].sort}
    assert_raise(ArgumentError) {[Float::NAN, 1].sort}
    assert_raise(ArgumentError) {[Float::NAN, 1.0].sort}
  end

  def test_to_a
    a = @cls[ 1, 2, 3 ]
    a_id = a.__id__
    assert_equal(a, a.to_a)
    assert_equal(a_id, a.to_a.__id__)
  end

  def test_to_ary
    a = [ 1, 2, 3 ]
    b = @cls[*a]

    a_id = a.__id__
    assert_equal(a, b.to_ary)
    if (@cls == Array)
      assert_equal(a_id, a.to_ary.__id__)
    end

    o = Object.new
    def o.to_ary
      [4, 5]
    end
    assert_equal([1, 2, 3, 4, 5], a.concat(o))

    o = Object.new
    def o.to_ary
      foo_bar()
    end
    assert_raise_with_message(NoMethodError, /foo_bar/) {a.concat(o)}
  end

  def test_to_s
    assert_deprecated_warning {$, = ""}
    a = @cls[]
    assert_equal("[]", a.to_s)

    assert_deprecated_warning {$, = ""}
    a = @cls[1, 2]
    assert_equal("[1, 2]", a.to_s)

    assert_deprecated_warning {$, = ""}
    a = @cls[1, 2, 3]
    assert_equal("[1, 2, 3]", a.to_s)

    assert_deprecated_warning {$, = ""}
    a = @cls[1, 2, 3]
    assert_equal("[1, 2, 3]", a.to_s)
  ensure
    $, = nil
  end

  StubToH = [
    [:key, :value],
    Object.new.tap do |kvp|
      def kvp.to_ary
        [:obtained, :via_to_ary]
      end
    end,
  ]

  def test_to_h
    array = StubToH
    assert_equal({key: :value, obtained: :via_to_ary}, array.to_h)

    e = assert_raise(TypeError) {
      [[:first_one, :ok], :not_ok].to_h
    }
    assert_equal "wrong element type Symbol at 1 (expected array)", e.message
    array = [eval("class C\u{1f5ff}; self; end").new]
    assert_raise_with_message(TypeError, /C\u{1f5ff}/) {array.to_h}
    e = assert_raise(ArgumentError) {
      [[:first_one, :ok], [1, 2], [:not_ok]].to_h
    }
    assert_equal "wrong array length at 2 (expected 2, was 1)", e.message
  end

  def test_to_h_block
    array = StubToH
    assert_equal({"key" => "value", "obtained" => "via_to_ary"},
                 array.to_h {|k, v| [k.to_s, v.to_s]})

    assert_equal({first_one: :ok, not_ok: :ng},
                 [[:first_one, :ok], :not_ok].to_h {|k, v| [k, v || :ng]})

    e = assert_raise(TypeError) {
      [[:first_one, :ok], :not_ok].to_h {|k, v| v ? [k, v] : k}
    }
    assert_equal "wrong element type Symbol at 1 (expected array)", e.message
    array = [1]
    k = eval("class C\u{1f5ff}; self; end").new
    assert_raise_with_message(TypeError, /C\u{1f5ff}/) {array.to_h {k}}
    e = assert_raise(ArgumentError) {
      [[:first_one, :ok], [1, 2], [:not_ok]].to_h {|kv| kv}
    }
    assert_equal "wrong array length at 2 (expected 2, was 1)", e.message
  end

  def test_min
    assert_equal(3, [3].min)
    assert_equal(1, [1, 2, 3, 1, 2].min)
    assert_equal(3, [1, 2, 3, 1, 2].min {|a,b| b <=> a })
    cond = ->((a, ia), (b, ib)) { (b <=> a).nonzero? or ia <=> ib }
    assert_equal([3, 2], [1, 2, 3, 1, 2].each_with_index.min(&cond))
    assert_equal(1.0, [3.0, 1.0, 2.0].min)
    ary = %w(albatross dog horse)
    assert_equal("albatross", ary.min)
    assert_equal("dog", ary.min {|a,b| a.length <=> b.length })
    assert_equal(1, [3,2,1].min)
    assert_equal(%w[albatross dog], ary.min(2))
    assert_equal(%w[dog horse],
                 ary.min(2) {|a,b| a.length <=> b.length })
    assert_equal([13, 14], [20, 32, 32, 21, 30, 25, 29, 13, 14].min(2))
    assert_equal([2, 4, 6, 7], [2, 4, 8, 6, 7].min(4))

    class << (obj = Object.new)
      def <=>(x) 1 <=> x end
      def coerce(x) [x, 1] end
    end
    assert_same(obj, [obj, 1.0].min)
  end

  def test_min_uncomparable
    assert_raise(ArgumentError) {[1, Float::NAN].min}
    assert_raise(ArgumentError) {[1.0, Float::NAN].min}
    assert_raise(ArgumentError) {[Float::NAN, 1].min}
    assert_raise(ArgumentError) {[Float::NAN, 1.0].min}
  end

  def test_max
    assert_equal(1, [1].max)
    assert_equal(3, [1, 2, 3, 1, 2].max)
    assert_equal(1, [1, 2, 3, 1, 2].max {|a,b| b <=> a })
    cond = ->((a, ia), (b, ib)) { (b <=> a).nonzero? or ia <=> ib }
    assert_equal([1, 3], [1, 2, 3, 1, 2].each_with_index.max(&cond))
    assert_equal(3.0, [1.0, 3.0, 2.0].max)
    ary = %w(albatross dog horse)
    assert_equal("horse", ary.max)
    assert_equal("albatross", ary.max {|a,b| a.length <=> b.length })
    assert_equal(1, [3,2,1].max{|a,b| b <=> a })
    assert_equal(%w[horse dog], ary.max(2))
    assert_equal(%w[albatross horse],
                 ary.max(2) {|a,b| a.length <=> b.length })
    assert_equal([3, 2], [0, 0, 0, 0, 0, 0, 1, 3, 2].max(2))

    class << (obj = Object.new)
      def <=>(x) 1 <=> x end
      def coerce(x) [x, 1] end
    end
    assert_same(obj, [obj, 1.0].max)
  end

  def test_max_uncomparable
    assert_raise(ArgumentError) {[1, Float::NAN].max}
    assert_raise(ArgumentError) {[1.0, Float::NAN].max}
    assert_raise(ArgumentError) {[Float::NAN, 1].max}
    assert_raise(ArgumentError) {[Float::NAN, 1.0].max}
  end

  def test_minmax
    assert_equal([3, 3], [3].minmax)
    assert_equal([1, 3], [1, 2, 3, 1, 2].minmax)
    assert_equal([3, 1], [1, 2, 3, 1, 2].minmax {|a,b| b <=> a })
    cond = ->((a, ia), (b, ib)) { (b <=> a).nonzero? or ia <=> ib }
    assert_equal([[3, 2], [1, 3]], [1, 2, 3, 1, 2].each_with_index.minmax(&cond))
    ary = %w(albatross dog horse)
    assert_equal(["albatross", "horse"], ary.minmax)
    assert_equal(["dog", "albatross"], ary.minmax {|a,b| a.length <=> b.length })
    assert_equal([1, 3], [3,2,1].minmax)

    class << (obj = Object.new)
      def <=>(x) 1 <=> x end
      def coerce(x) [x, 1] end
    end
    ary = [obj, 1.0].minmax
    assert_same(obj, ary[0])
    assert_equal(obj, ary[1])
  end

  def test_uniq
    a = []
    b = a.uniq
    assert_equal([], a)
    assert_equal([], b)
    assert_not_same(a, b)

    a = [1]
    b = a.uniq
    assert_equal([1], a)
    assert_equal([1], b)
    assert_not_same(a, b)

    a = [1,1]
    b = a.uniq
    assert_equal([1,1], a)
    assert_equal([1], b)
    assert_not_same(a, b)

    a = [1,2]
    b = a.uniq
    assert_equal([1,2], a)
    assert_equal([1,2], b)
    assert_not_same(a, b)

    a = @cls[ 1, 2, 3, 2, 1, 2, 3, 4, nil ]
    b = a.dup
    assert_equal(@cls[1, 2, 3, 4, nil], a.uniq)
    assert_equal(b, a)

    c = @cls["a:def", "a:xyz", "b:abc", "b:xyz", "c:jkl"]
    d = c.dup
    assert_equal(@cls[ "a:def", "b:abc", "c:jkl" ], c.uniq {|s| s[/^\w+/]})
    assert_equal(d, c)

    assert_equal(@cls[1, 2, 3], @cls[1, 2, 3].uniq)

    a = %w(a a)
    b = a.uniq
    assert_equal(%w(a a), a)
    assert(a.none?(&:frozen?))
    assert_equal(%w(a), b)
    assert(b.none?(&:frozen?))

    bug9340 = "[ruby-core:59457]"
    ary = [bug9340, bug9340.dup, bug9340.dup]
    assert_equal 1, ary.uniq.size
    assert_same bug9340, ary.uniq[0]

    sc = Class.new(@cls)
    a = sc[]
    b = a.dup
    assert_equal_instance([], a.uniq)
    assert_equal(b, a)

    a = sc[1]
    b = a.dup
    assert_equal_instance([1], a.uniq)
    assert_equal(b, a)

    a = sc[1, 1]
    b = a.dup
    assert_equal_instance([1], a.uniq)
    assert_equal(b, a)

    a = sc[1, 1]
    b = a.dup
    assert_equal_instance([1], a.uniq{|x| x})
    assert_equal(b, a)
  end

  def test_uniq_with_block
    a = []
    b = a.uniq {|v| v.even? }
    assert_equal([], a)
    assert_equal([], b)
    assert_not_same(a, b)

    a = [1]
    b = a.uniq {|v| v.even? }
    assert_equal([1], a)
    assert_equal([1], b)
    assert_not_same(a, b)

    a = [1,3]
    b = a.uniq {|v| v.even? }
    assert_equal([1,3], a)
    assert_equal([1], b)
    assert_not_same(a, b)

    a = %w(a a)
    b = a.uniq {|v| v }
    assert_equal(%w(a a), a)
    assert(a.none?(&:frozen?))
    assert_equal(%w(a), b)
    assert(b.none?(&:frozen?))
  end

  def test_uniq!
    a = []
    b = a.uniq!
    assert_equal(nil, b)

    a = [1]
    b = a.uniq!
    assert_equal(nil, b)

    a = [1,1]
    b = a.uniq!
    assert_equal([1], a)
    assert_equal([1], b)
    assert_same(a, b)

    a = [1,2]
    b = a.uniq!
    assert_equal([1,2], a)
    assert_equal(nil, b)

    a = @cls[ 1, 2, 3, 2, 1, 2, 3, 4, nil ]
    assert_equal(@cls[1, 2, 3, 4, nil], a.uniq!)
    assert_equal(@cls[1, 2, 3, 4, nil], a)

    c = @cls["a:def", "a:xyz", "b:abc", "b:xyz", "c:jkl"]
    assert_equal(@cls[ "a:def", "b:abc", "c:jkl" ], c.uniq! {|s| s[/^\w+/]})
    assert_equal(@cls[ "a:def", "b:abc", "c:jkl" ], c)

    c = @cls["a:def", "b:abc", "c:jkl"]
    assert_equal(nil, c.uniq! {|s| s[/^\w+/]})
    assert_equal(@cls[ "a:def", "b:abc", "c:jkl" ], c)

    assert_nil(@cls[1, 2, 3].uniq!)

    f = a.dup.freeze
    assert_raise(ArgumentError) { a.uniq!(1) }
    assert_raise(ArgumentError) { f.uniq!(1) }
    assert_raise(FrozenError) { f.uniq! }

    assert_nothing_raised do
      a = [ {c: "b"}, {c: "r"}, {c: "w"}, {c: "g"}, {c: "g"} ]
      a.sort_by!{|e| e[:c]}
      a.uniq!   {|e| e[:c]}
    end

    a = %w(a a)
    b = a.uniq
    assert_equal(%w(a a), a)
    assert(a.none?(&:frozen?))
    assert_equal(%w(a), b)
    assert(b.none?(&:frozen?))
  end

  def test_uniq_bang_with_block
    a = []
    b = a.uniq! {|v| v.even? }
    assert_equal(nil, b)

    a = [1]
    b = a.uniq! {|v| v.even? }
    assert_equal(nil, b)

    a = [1,3]
    b = a.uniq! {|v| v.even? }
    assert_equal([1], a)
    assert_equal([1], b)
    assert_same(a, b)

    a = [1,2]
    b = a.uniq! {|v| v.even? }
    assert_equal([1,2], a)
    assert_equal(nil, b)

    a = %w(a a)
    b = a.uniq! {|v| v }
    assert_equal(%w(a), b)
    assert_same(a, b)
    assert b.none?(&:frozen?)
  end

  def test_uniq_bang_with_freeze
    ary = [1,2]
    orig = ary.dup
    assert_raise(FrozenError, "frozen during comparison") {
      ary.uniq! {|v| ary.freeze; 1}
    }
    assert_equal(orig, ary, "must not be modified once frozen")
  end

  def test_unshift
    a = @cls[]
    assert_equal(@cls['cat'], a.unshift('cat'))
    assert_equal(@cls['dog', 'cat'], a.unshift('dog'))
    assert_equal(@cls[nil, 'dog', 'cat'], a.unshift(nil))
    assert_equal(@cls[@cls[1,2], nil, 'dog', 'cat'], a.unshift(@cls[1, 2]))
  end

  def test_unshift_frozen
    bug15952 = '[Bug #15952]'
    assert_raise(FrozenError, bug15952) do
      a = [1] * 100
      b = a[4..-1]
      a.replace([1])
      b.freeze
      b.unshift("a")
    end
  end

  def test_OR # '|'
    assert_equal(@cls[],  @cls[]  | @cls[])
    assert_equal(@cls[1], @cls[1] | @cls[])
    assert_equal(@cls[1], @cls[]  | @cls[1])
    assert_equal(@cls[1], @cls[1] | @cls[1])

    assert_equal(@cls[1,2], @cls[1] | @cls[2])
    assert_equal(@cls[1,2], @cls[1, 1] | @cls[2, 2])
    assert_equal(@cls[1,2], @cls[1, 2] | @cls[1, 2])

    a = %w(a b c)
    b = %w(a b c d e)
    c = a | b
    assert_equal(c, b)
    assert_not_same(c, b)
    assert_equal(%w(a b c), a)
    assert_equal(%w(a b c d e), b)
    assert(a.none?(&:frozen?))
    assert(b.none?(&:frozen?))
    assert(c.none?(&:frozen?))
  end

  def test_OR_in_order
    obj1, obj2 = Class.new do
      attr_reader :name
      def initialize(name) @name = name; end
      def inspect; "test_OR_in_order(#{@name})"; end
      def hash; 0; end
      def eql?(a) true; end
      break [new("1"), new("2")]
    end
    assert_equal([obj1], [obj1]|[obj2])
  end

  def test_OR_big_in_order
    obj1, obj2 = Class.new do
      attr_reader :name
      def initialize(name) @name = name; end
      def inspect; "test_OR_in_order(#{@name})"; end
      def hash; 0; end
      def eql?(a) true; end
      break [new("1"), new("2")]
    end
    assert_equal([obj1], [obj1]*64|[obj2]*64)
  end

  def test_OR_big_array # '|'
    assert_equal(@cls[1,2], @cls[1]*64 | @cls[2]*64)
    assert_equal(@cls[1,2], @cls[1, 2]*64 | @cls[1, 2]*64)

    a = (1..64).to_a
    b = (1..128).to_a
    c = a | b
    assert_equal(c, b)
    assert_not_same(c, b)
    assert_equal((1..64).to_a, a)
    assert_equal((1..128).to_a, b)
  end

  def test_union
    assert_equal(@cls[],  @cls[].union(@cls[]))
    assert_equal(@cls[1], @cls[1].union(@cls[]))
    assert_equal(@cls[1], @cls[].union(@cls[1]))
    assert_equal(@cls[1], @cls[].union(@cls[], @cls[1]))
    assert_equal(@cls[1], @cls[1].union(@cls[1]))
    assert_equal(@cls[1], @cls[1].union(@cls[1], @cls[1], @cls[1]))

    assert_equal(@cls[1,2], @cls[1].union(@cls[2]))
    assert_equal(@cls[1,2], @cls[1, 1].union(@cls[2, 2]))
    assert_equal(@cls[1,2], @cls[1, 2].union(@cls[1, 2]))
    assert_equal(@cls[1,2], @cls[1, 1].union(@cls[1, 1], @cls[1, 2], @cls[2, 1], @cls[2, 2, 2]))

    a = %w(a b c)
    b = %w(a b c d e)
    c = a.union(b)
    assert_equal(c, b)
    assert_not_same(c, b)
    assert_equal(%w(a b c), a)
    assert_equal(%w(a b c d e), b)
    assert(a.none?(&:frozen?))
    assert(b.none?(&:frozen?))
    assert(c.none?(&:frozen?))
  end

  def test_union_big_array
    assert_equal(@cls[1,2], (@cls[1]*64).union(@cls[2]*64))
    assert_equal(@cls[1,2,3], (@cls[1, 2]*64).union(@cls[1, 2]*64, @cls[3]*60))

    a = (1..64).to_a
    b = (1..128).to_a
    c = a | b
    assert_equal(c, b)
    assert_not_same(c, b)
    assert_equal((1..64).to_a, a)
    assert_equal((1..128).to_a, b)
  end

  def test_combination
    a = @cls[]
    assert_equal(1, a.combination(0).size)
    assert_equal(0, a.combination(1).size)
    a = @cls[1,2,3,4]
    assert_equal(1, a.combination(0).size)
    assert_equal(4, a.combination(1).size)
    assert_equal(6, a.combination(2).size)
    assert_equal(4, a.combination(3).size)
    assert_equal(1, a.combination(4).size)
    assert_equal(0, a.combination(5).size)
    assert_equal(@cls[[]], a.combination(0).to_a)
    assert_equal(@cls[[1],[2],[3],[4]], a.combination(1).to_a)
    assert_equal(@cls[[1,2],[1,3],[1,4],[2,3],[2,4],[3,4]], a.combination(2).to_a)
    assert_equal(@cls[[1,2,3],[1,2,4],[1,3,4],[2,3,4]], a.combination(3).to_a)
    assert_equal(@cls[[1,2,3,4]], a.combination(4).to_a)
    assert_equal(@cls[], a.combination(5).to_a)
  end

  def test_product
    assert_equal(@cls[[1,4],[1,5],[2,4],[2,5],[3,4],[3,5]],
                 @cls[1,2,3].product([4,5]))
    assert_equal(@cls[[1,1],[1,2],[2,1],[2,2]], @cls[1,2].product([1,2]))

    assert_equal(@cls[[1,3,5],[1,3,6],[1,4,5],[1,4,6],
                   [2,3,5],[2,3,6],[2,4,5],[2,4,6]],
                 @cls[1,2].product([3,4],[5,6]))
    assert_equal(@cls[[1],[2]], @cls[1,2].product)
    assert_equal(@cls[], @cls[1,2].product([]))

    bug3394 = '[ruby-dev:41540]'
    acc = []
    EnvUtil.under_gc_stress {[1,2].product([3,4,5],[6,8]){|array| acc << array}}
    assert_equal([[1, 3, 6], [1, 3, 8], [1, 4, 6], [1, 4, 8], [1, 5, 6], [1, 5, 8],
                  [2, 3, 6], [2, 3, 8], [2, 4, 6], [2, 4, 8], [2, 5, 6], [2, 5, 8]],
                 acc, bug3394)

    def (o = Object.new).to_ary; GC.start; [3,4] end
    acc = [1,2].product(*[o]*10)
    assert_equal([1,2].product([3,4], [3,4], [3,4], [3,4], [3,4], [3,4], [3,4], [3,4], [3,4], [3,4]),
                 acc)

    a = []
    [1, 2].product([0, 1, 2, 3, 4][1, 4]) {|x| a << x }
    a.all? {|x| assert_not_include(x, 0)}
  end

  def test_permutation
    a = @cls[]
    assert_equal(1, a.permutation(0).size)
    assert_equal(0, a.permutation(1).size)
    a = @cls[1,2,3]
    assert_equal(1, a.permutation(0).size)
    assert_equal(3, a.permutation(1).size)
    assert_equal(6, a.permutation(2).size)
    assert_equal(6, a.permutation(3).size)
    assert_equal(0, a.permutation(4).size)
    assert_equal(6, a.permutation.size)
    assert_equal(@cls[[]], a.permutation(0).to_a)
    assert_equal(@cls[[1],[2],[3]], a.permutation(1).to_a.sort)
    assert_equal(@cls[[1,2],[1,3],[2,1],[2,3],[3,1],[3,2]],
                 a.permutation(2).to_a.sort)
    assert_equal(@cls[[1,2,3],[1,3,2],[2,1,3],[2,3,1],[3,1,2],[3,2,1]],
                 a.permutation(3).sort.to_a)
    assert_equal(@cls[], a.permutation(4).to_a)
    assert_equal(@cls[], a.permutation(-1).to_a)
    assert_equal("abcde".each_char.to_a.permutation(5).sort,
                 "edcba".each_char.to_a.permutation(5).sort)
    assert_equal(@cls[].permutation(0).to_a, @cls[[]])

    a = @cls[1, 2, 3, 4]
    b = @cls[]
    a.permutation {|x| b << x; a.replace(@cls[9, 8, 7, 6]) }
    assert_equal(@cls[9, 8, 7, 6], a)
    assert_equal(@cls[1, 2, 3, 4].permutation.to_a, b)

    bug3708 = '[ruby-dev:42067]'
    assert_equal(b, @cls[0, 1, 2, 3, 4][1, 4].permutation.to_a, bug3708)
  end

  def test_permutation_stack_error
    bug9932 = '[ruby-core:63103] [Bug #9932]'
    assert_separately([], "#{<<~"begin;"}\n#{<<~'end;'}", timeout: 30)
    bug = "#{bug9932}"
    begin;
      assert_nothing_raised(SystemStackError, bug) do
        assert_equal(:ok, Array.new(100_000, nil).permutation {break :ok})
      end
    end;
  end

  def test_repeated_permutation
    a = @cls[]
    assert_equal(1, a.repeated_permutation(0).size)
    assert_equal(0, a.repeated_permutation(1).size)
    a = @cls[1,2]
    assert_equal(1, a.repeated_permutation(0).size)
    assert_equal(2, a.repeated_permutation(1).size)
    assert_equal(4, a.repeated_permutation(2).size)
    assert_equal(8, a.repeated_permutation(3).size)
    assert_equal(@cls[[]], a.repeated_permutation(0).to_a)
    assert_equal(@cls[[1],[2]], a.repeated_permutation(1).to_a.sort)
    assert_equal(@cls[[1,1],[1,2],[2,1],[2,2]],
                 a.repeated_permutation(2).to_a.sort)
    assert_equal(@cls[[1,1,1],[1,1,2],[1,2,1],[1,2,2],
                      [2,1,1],[2,1,2],[2,2,1],[2,2,2]],
                 a.repeated_permutation(3).to_a.sort)
    assert_equal(@cls[], a.repeated_permutation(-1).to_a)
    assert_equal("abcde".each_char.to_a.repeated_permutation(5).sort,
                 "edcba".each_char.to_a.repeated_permutation(5).sort)
    assert_equal(@cls[].repeated_permutation(0).to_a, @cls[[]])
    assert_equal(@cls[].repeated_permutation(1).to_a, @cls[])

    a = @cls[1, 2, 3, 4]
    b = @cls[]
    a.repeated_permutation(4) {|x| b << x; a.replace(@cls[9, 8, 7, 6]) }
    assert_equal(@cls[9, 8, 7, 6], a)
    assert_equal(@cls[1, 2, 3, 4].repeated_permutation(4).to_a, b)

    a = @cls[0, 1, 2, 3, 4][1, 4].repeated_permutation(2)
    assert_empty(a.reject {|x| !x.include?(0)})
  end

  def test_repeated_permutation_stack_error
    assert_separately([], "#{<<-"begin;"}\n#{<<~'end;'}", timeout: 30)
    begin;
      assert_nothing_raised(SystemStackError) do
        assert_equal(:ok, Array.new(100_000, nil).repeated_permutation(500_000) {break :ok})
      end
    end;
  end

  def test_repeated_combination
    a = @cls[]
    assert_equal(1, a.repeated_combination(0).size)
    assert_equal(0, a.repeated_combination(1).size)
    a = @cls[1,2,3]
    assert_equal(1, a.repeated_combination(0).size)
    assert_equal(3, a.repeated_combination(1).size)
    assert_equal(6, a.repeated_combination(2).size)
    assert_equal(10, a.repeated_combination(3).size)
    assert_equal(15, a.repeated_combination(4).size)
    assert_equal(@cls[[]], a.repeated_combination(0).to_a)
    assert_equal(@cls[[1],[2],[3]], a.repeated_combination(1).to_a.sort)
    assert_equal(@cls[[1,1],[1,2],[1,3],[2,2],[2,3],[3,3]],
                 a.repeated_combination(2).to_a.sort)
    assert_equal(@cls[[1,1,1],[1,1,2],[1,1,3],[1,2,2],[1,2,3],
                      [1,3,3],[2,2,2],[2,2,3],[2,3,3],[3,3,3]],
                 a.repeated_combination(3).to_a.sort)
    assert_equal(@cls[[1,1,1,1],[1,1,1,2],[1,1,1,3],[1,1,2,2],[1,1,2,3],
                      [1,1,3,3],[1,2,2,2],[1,2,2,3],[1,2,3,3],[1,3,3,3],
                      [2,2,2,2],[2,2,2,3],[2,2,3,3],[2,3,3,3],[3,3,3,3]],
                 a.repeated_combination(4).to_a.sort)
    assert_equal(@cls[], a.repeated_combination(-1).to_a)
    assert_equal("abcde".each_char.to_a.repeated_combination(5).map{|e|e.sort}.sort,
                 "edcba".each_char.to_a.repeated_combination(5).map{|e|e.sort}.sort)
    assert_equal(@cls[].repeated_combination(0).to_a, @cls[[]])
    assert_equal(@cls[].repeated_combination(1).to_a, @cls[])

    a = @cls[1, 2, 3, 4]
    b = @cls[]
    a.repeated_combination(4) {|x| b << x; a.replace(@cls[9, 8, 7, 6]) }
    assert_equal(@cls[9, 8, 7, 6], a)
    assert_equal(@cls[1, 2, 3, 4].repeated_combination(4).to_a, b)

    a = @cls[0, 1, 2, 3, 4][1, 4].repeated_combination(2)
    assert_empty(a.reject {|x| !x.include?(0)})
  end

  def test_repeated_combination_stack_error
    assert_separately([], "#{<<~"begin;"}\n#{<<~'end;'}", timeout: 20)
    begin;
      assert_nothing_raised(SystemStackError) do
        assert_equal(:ok, Array.new(100_000, nil).repeated_combination(500_000) {break :ok})
      end
    end;
  end

  def test_take
    assert_equal_instance([1,2,3], @cls[1,2,3,4,5,0].take(3))
    assert_raise(ArgumentError, '[ruby-dev:34123]') { [1,2].take(-1) }
    assert_equal_instance([1,2], @cls[1,2].take(1000000000), '[ruby-dev:34123]')
  end

  def test_take_while
    assert_equal_instance([1,2], @cls[1,2,3,4,5,0].take_while {|i| i < 3 })
  end

  def test_drop
    assert_equal_instance([4,5,0], @cls[1,2,3,4,5,0].drop(3))
    assert_raise(ArgumentError, '[ruby-dev:34123]') { [1,2].drop(-1) }
    assert_equal_instance([], @cls[1,2].drop(1000000000), '[ruby-dev:34123]')
  end

  def test_drop_while
    assert_equal_instance([3,4,5,0], @cls[1,2,3,4,5,0].drop_while {|i| i < 3 })
  end

  LONGP = [127, 63, 31, 15, 7].map {|x| 2**x-1 }.find do |x|
    begin
      [].first(x)
    rescue ArgumentError
      true
    rescue RangeError
      false
    end
  end

  def test_ary_new
    assert_raise(ArgumentError) { [].to_enum.first(-1) }
    assert_raise(ArgumentError) { [].to_enum.first(LONGP) }
  end

  def test_try_convert
    assert_equal([1], Array.try_convert([1]))
    assert_equal(nil, Array.try_convert("1"))
  end

  def test_initialize
    assert_nothing_raised { [].instance_eval { initialize } }
    assert_warning(/given block not used/) { Array.new { } }
    assert_equal([1, 2, 3], Array.new([1, 2, 3]))
    assert_raise(ArgumentError) { Array.new(-1, 1) }
    assert_raise(ArgumentError) { Array.new(LONGP, 1) }
    assert_equal([1, 1, 1], Array.new(3, 1))
    assert_equal([1, 1, 1], Array.new(3) { 1 })
    assert_equal([1, 1, 1], assert_warning(/block supersedes default value argument/) {Array.new(3, 1) { 1 }})
  end

  def test_aset_error
    assert_raise(IndexError) { [0][-2] = 1 }
    assert_raise(IndexError) { [0][LONGP] = 2 }
    assert_raise(IndexError) { [0][(LONGP + 1) / 2 - 1] = 2 }
    assert_raise(IndexError) { [0][LONGP..-1] = 2 }
    assert_raise(IndexError) { [0][LONGP..] = 2 }
    a = [0]
    a[2] = 4
    assert_equal([0, nil, 4], a)
    assert_raise(ArgumentError) { [0][0, 0, 0] = 0 }
    assert_raise(ArgumentError) { [0].freeze[0, 0, 0] = 0 }
    assert_raise(TypeError) { [0][:foo] = 0 }
    assert_raise(FrozenError) { [0].freeze[:foo] = 0 }

    # [Bug #17271]
    assert_raise_with_message(RangeError, "-7.. out of range") { [*0..5][-7..] = 1 }
  end

  def test_first2
    assert_equal([0], [0].first(2))
    assert_raise(ArgumentError) { [0].first(-1) }
  end

  def test_last2
    assert_equal([0], [0].last(2))
    assert_raise(ArgumentError) { [0].last(-1) }
  end

  def test_shift2
    assert_equal(0, ([0] * 16).shift)
    # check
    a = [0, 1, 2]
    a[3] = 3
    a.shift(2)
    assert_equal([2, 3], a)

    assert_equal([1,1,1], ([1] * 100).shift(3))
  end

  def test_unshift_error
    assert_raise(FrozenError) { [].freeze.unshift('cat') }
    assert_raise(FrozenError) { [].freeze.unshift() }
  end

  def test_aref
    assert_raise(ArgumentError) { [][0, 0, 0] }
    assert_raise(ArgumentError) { @cls[][0, 0, 0] }
  end

  def test_fetch
    assert_equal(1, assert_warning(/block supersedes default value argument/) {[].fetch(0, 0) { 1 }})
    assert_equal(1, [0, 1].fetch(-1))
    assert_raise(IndexError) { [0, 1].fetch(2) }
    assert_raise(IndexError) { [0, 1].fetch(-3) }
    assert_equal(2, [0, 1].fetch(2, 2))
  end

  def test_index2
    a = [0, 1, 2]
    assert_equal(a, a.index.to_a)
    assert_equal(1, a.index {|x| x == 1 })
  end

  def test_rindex2
    a = [0, 1, 2]
    assert_equal([2, 1, 0], a.rindex.to_a)
    assert_equal(1, a.rindex {|x| x == 1 })

    a = [0, 1]
    e = a.rindex
    assert_equal(1, e.next)
    a.clear
    assert_raise(StopIteration) { e.next }

    o = Object.new
    class << o; self; end.class_eval do
      define_method(:==) {|x| a.clear; false }
    end
    a = [nil, o]
    assert_equal(nil, a.rindex(0))
  end

  def test_ary_to_ary
    o = Object.new
    def o.to_ary; [1, 2, 3]; end
    a, b, c = o
    assert_equal([1, 2, 3], [a, b, c])
  end

  def test_splice
    a = [0]
    assert_raise(IndexError) { a[-2, 0] = nil }
  end

  def test_insert
    a = [0]
    assert_equal([0], a.insert(1))
    assert_equal([0, 1], a.insert(1, 1))
    assert_raise(ArgumentError) { a.insert }
    assert_raise(TypeError) { a.insert(Object.new) }
    assert_equal([0, 1, 2], a.insert(-1, 2))
    assert_equal([0, 1, 3, 2], a.insert(-2, 3))
    assert_raise_with_message(IndexError, /-6/) { a.insert(-6, 4) }
    assert_raise(FrozenError) { [0].freeze.insert(0)}
    assert_raise(ArgumentError) { [0].freeze.insert }
  end

  def test_join2
    a = []
    a << a
    assert_raise(ArgumentError){a.join}

    def (a = Object.new).to_ary
      [self]
    end
    assert_raise(ArgumentError, '[ruby-core:24150]'){[a].join}
    assert_equal("12345", [1,[2,[3,4],5]].join)
  end

  def test_join_recheck_elements_type
    x = Struct.new(:ary).new
    def x.to_str
      ary[2] = [0, 1, 2]
      "z"
    end
    (x.ary = ["a", "b", "c", x])
    assert_equal("ab012z", x.ary.join(""))
  end

  def test_join_recheck_array_length
    x = Struct.new(:ary).new
    def x.to_str
      ary.clear
      ary[0] = "b"
      "z"
    end
    x.ary = Array.new(1023) {"a"*1} << x
    assert_equal("b", x.ary.join(""))
  end

  def test_to_a2
    klass = Class.new(Array)
    a = klass.new.to_a
    assert_equal([], a)
    assert_equal(Array, a.class)
  end

  def test_values_at2
    a = [0, 1, 2, 3, 4, 5]
    assert_equal([1, 2, 3], a.values_at(1..3))
    assert_equal([nil, nil], a.values_at(7..8))
    bug6203 = '[ruby-core:43678]'
    assert_equal([4, 5, nil, nil], a.values_at(4..7), bug6203)
    assert_equal([nil], a.values_at(2**31-1))
  end

  def test_select
    assert_equal([0, 2], [0, 1, 2, 3].select {|x| x % 2 == 0 })
  end

  # also keep_if
  def test_select!
    a = @cls[ 1, 2, 3, 4, 5 ]
    assert_equal(nil, a.select! { true })
    assert_equal(@cls[1, 2, 3, 4, 5], a)

    a = @cls[ 1, 2, 3, 4, 5 ]
    assert_equal(a, a.select! { false })
    assert_equal(@cls[], a)

    a = @cls[ 1, 2, 3, 4, 5 ]
    assert_equal(a, a.select! { |i| i > 3 })
    assert_equal(@cls[4, 5], a)

    bug10722 = '[ruby-dev:48805] [Bug #10722]'
    a = @cls[ 5, 6, 7, 8, 9, 10 ]
    r = a.select! {|i|
      break i if i > 8
      # assert_equal(a[0], i, "should be selected values only") if i == 7
      i >= 7
    }
    assert_equal(9, r)
    assert_equal(@cls[7, 8, 9, 10], a, bug10722)

    bug13053 = '[ruby-core:78739] [Bug #13053] Array#select! can resize to negative size'
    a = @cls[ 1, 2, 3, 4, 5 ]
    a.select! {|i| a.clear if i == 5; false }
    assert_equal(0, a.size, bug13053)

    assert_raise(FrozenError) do
      a = @cls[1, 2, 3, 42]
      a.select! do
        a.freeze
        false
      end
    end
    assert_equal(@cls[1, 2, 3, 42], a)
  end

  # also select!
  def test_keep_if
    a = @cls[ 1, 2, 3, 4, 5 ]
    assert_equal(a, a.keep_if { true })
    assert_equal(@cls[1, 2, 3, 4, 5], a)

    a = @cls[ 1, 2, 3, 4, 5 ]
    assert_equal(a, a.keep_if { false })
    assert_equal(@cls[], a)

    a = @cls[ 1, 2, 3, 4, 5 ]
    assert_equal(a, a.keep_if { |i| i > 3 })
    assert_equal(@cls[4, 5], a)

    assert_raise(FrozenError) do
      a = @cls[1, 2, 3, 42]
      a.keep_if do
        a.freeze
        false
      end
    end
    assert_equal(@cls[1, 2, 3, 42], a)
  end

  def test_filter
    assert_equal([0, 2], [0, 1, 2, 3].filter {|x| x % 2 == 0 })
  end

  # alias for select!
  def test_filter!
    a = @cls[ 1, 2, 3, 4, 5 ]
    assert_equal(nil, a.filter! { true })
    assert_equal(@cls[1, 2, 3, 4, 5], a)

    a = @cls[ 1, 2, 3, 4, 5 ]
    assert_equal(a, a.filter! { false })
    assert_equal(@cls[], a)

    a = @cls[ 1, 2, 3, 4, 5 ]
    assert_equal(a, a.filter! { |i| i > 3 })
    assert_equal(@cls[4, 5], a)
  end

  def test_delete2
    a = [0] * 1024 + [1] + [0] * 1024
    a.delete(0)
    assert_equal([1], a)
  end

  def test_reject
    assert_equal([1, 3], [0, 1, 2, 3].reject {|x| x % 2 == 0 })
  end

  def test_reject_with_callcc
    need_continuation
    bug9727 = '[ruby-dev:48101] [Bug #9727]'
    cont = nil
    a = [*1..10].reject do |i|
      callcc {|c| cont = c} if !cont and i == 10
      false
    end
    if a.size < 1000
      a.unshift(:x)
      cont.call
    end
    assert_equal(1000, a.size, bug9727)
    assert_equal([:x, *1..10], a.uniq, bug9727)
  end

  def test_zip
    assert_equal([[1, :a, "a"], [2, :b, "b"], [3, nil, "c"]],
      [1, 2, 3].zip([:a, :b], ["a", "b", "c", "d"]))
    a = []
    [1, 2, 3].zip([:a, :b], ["a", "b", "c", "d"]) {|x| a << x }
    assert_equal([[1, :a, "a"], [2, :b, "b"], [3, nil, "c"]], a)

    ary = Object.new
    def ary.to_a;   [1, 2]; end
    assert_raise(TypeError) {%w(a b).zip(ary)}
    def ary.each; [3, 4].each{|e|yield e}; end
    assert_equal([['a', 3], ['b', 4]], %w(a b).zip(ary))
    def ary.to_ary; [5, 6]; end
    assert_equal([['a', 5], ['b', 6]], %w(a b).zip(ary))
  end

  def test_zip_bug
    bug8153 = "ruby-core:53650"
    r = [1]
    def r.respond_to?(*)
      super
    end
    assert_equal [[42, 1]], [42].zip(r), bug8153
  end

  def test_zip_with_enumerator
    bug17814 = "ruby-core:103513"

    step = 0.step
    e = Enumerator.produce { step.next }
    a = %w(a b c)
    assert_equal([["a", 0], ["b", 1], ["c", 2]], a.zip(e), bug17814)
    assert_equal([["a", 3], ["b", 4], ["c", 5]], a.zip(e), bug17814)
    assert_equal([["a", 6], ["b", 7], ["c", 8]], a.zip(e), bug17814)
  end

  def test_transpose
    assert_equal([[1, :a], [2, :b], [3, :c]],
      [[1, 2, 3], [:a, :b, :c]].transpose)
    assert_raise(IndexError) { [[1, 2, 3], [:a, :b]].transpose }
  end

  def test_clear2
    assert_equal([], ([0] * 1024).clear)
  end

  def test_fill2
    assert_raise(ArgumentError) { [].fill(0, 1, LONGP) }
  end

  def test_times
    assert_raise(ArgumentError) { [0, 0, 0, 0] * ((LONGP + 1) / 4) }
  end

  def test_equal
    o = Object.new
    def o.to_ary; end
    def o.==(x); :foo; end
    assert_equal([0, 1, 2], o)
    assert_not_equal([0, 1, 2], [0, 1, 3])
  end

  def test_equal_resize
    $test_equal_resize_a = Array.new(3, &:to_s)
    $test_equal_resize_b = $test_equal_resize_a.dup
    o = Object.new
    def o.==(o)
      $test_equal_resize_a.clear
      $test_equal_resize_b.clear
      true
    end
    $test_equal_resize_a[1] = o
    assert_equal($test_equal_resize_a, $test_equal_resize_b)
  end

  def test_flatten_error
    a = []
    f = [].freeze
    assert_raise(ArgumentError) { a.flatten!(1, 2) }
    assert_raise(TypeError) { a.flatten!(:foo) }
    assert_raise(ArgumentError) { f.flatten!(1, 2) }
    assert_raise(FrozenError) { f.flatten! }
    assert_raise(FrozenError) { f.flatten!(:foo) }
  end

  def test_shuffle
    100.times do
      assert_equal([0, 1, 2], [2, 1, 0].shuffle.sort)
    end

    gen = Random.new(0)
    assert_raise(ArgumentError) {[1, 2, 3].shuffle(1, random: gen)}
    srand(0)
    100.times do
      assert_equal([0, 1, 2].shuffle, [0, 1, 2].shuffle(random: gen))
    end

    assert_raise_with_message(ArgumentError, /unknown keyword/) do
      [0, 1, 2].shuffle(xawqij: "a")
    end
    assert_raise_with_message(ArgumentError, /unknown keyword/) do
      [0, 1, 2].shuffle!(xawqij: "a")
    end
  end

  def test_shuffle_random
    gen = proc do
      10000000
    end
    class << gen
      alias rand call
    end
    assert_raise(RangeError) {
      [*0..2].shuffle(random: gen)
    }
  end

  def test_shuffle_random_clobbering
    ary = (0...10000).to_a
    gen = proc do
      ary.replace([])
      0.5
    end
    class << gen
      alias rand call
    end
    assert_raise(RuntimeError) {ary.shuffle!(random: gen)}
  end

  def test_shuffle_random_zero
    zero = Object.new
    def zero.to_int
      0
    end
    gen_to_int = proc do |max|
      zero
    end
    class << gen_to_int
      alias rand call
    end
    ary = (0...10000).to_a
    assert_equal(ary.rotate, ary.shuffle(random: gen_to_int))
  end

  def test_shuffle_random_invalid_generator
    ary = (0...10).to_a
    assert_raise(NoMethodError) {
      ary.shuffle(random: Object.new)
    }
    assert_raise(NoMethodError) {
      ary.shuffle!(random: Object.new)
    }
  end

  def test_sample
    100.times do
      assert_include([0, 1, 2], [2, 1, 0].sample)
      samples = [2, 1, 0].sample(2)
      samples.each{|sample|
        assert_include([0, 1, 2], sample)
      }
    end
  end

  def test_sample_statistics
    srand(0)
    a = (1..18).to_a
    (0..20).each do |n|
      100.times do
        b = a.sample(n)
        assert_equal([n, 18].min, b.size)
        assert_equal(a, (a | b).sort)
        assert_equal(b.sort, (a & b).sort)
      end

      h = Hash.new(0)
      1000.times do
        a.sample(n).each {|x| h[x] += 1 }
      end
      assert_operator(h.values.min * 2, :>=, h.values.max) if n != 0
    end
  end

  def test_sample_invalid_argument
    assert_raise(ArgumentError, '[ruby-core:23374]') {[1, 2].sample(-1)}
  end

  def test_sample_random_srand0
    gen = Random.new(0)
    srand(0)
    a = (1..18).to_a
    (0..20).each do |n|
      100.times do |i|
        assert_equal(a.sample(n), a.sample(n, random: gen), "#{i}/#{n}")
      end
    end
  end

  def test_sample_unknown_keyword
    assert_raise_with_message(ArgumentError, /unknown keyword/) do
      [0, 1, 2].sample(xawqij: "a")
    end
  end

  def test_sample_random_generator
    ary = (0...10000).to_a
    assert_raise(ArgumentError) {ary.sample(1, 2, random: nil)}
    gen0 = proc do |max|
      max/2
    end
    class << gen0
      alias rand call
    end
    gen1 = proc do |max|
      ary.replace([])
      max/2
    end
    class << gen1
      alias rand call
    end
    assert_equal(5000, ary.sample(random: gen0))
    assert_nil(ary.sample(random: gen1))
    assert_equal([], ary)
    ary = (0...10000).to_a
    assert_equal([5000], ary.sample(1, random: gen0))
    assert_equal([], ary.sample(1, random: gen1))
    assert_equal([], ary)
    ary = (0...10000).to_a
    assert_equal([5000, 4999], ary.sample(2, random: gen0))
    assert_equal([], ary.sample(2, random: gen1))
    assert_equal([], ary)
    ary = (0...10000).to_a
    assert_equal([5000, 4999, 5001], ary.sample(3, random: gen0))
    assert_equal([], ary.sample(3, random: gen1))
    assert_equal([], ary)
    ary = (0...10000).to_a
    assert_equal([5000, 4999, 5001, 4998], ary.sample(4, random: gen0))
    assert_equal([], ary.sample(4, random: gen1))
    assert_equal([], ary)
    ary = (0...10000).to_a
    assert_equal([5000, 4999, 5001, 4998, 5002, 4997, 5003, 4996, 5004, 4995], ary.sample(10, random: gen0))
    assert_equal([], ary.sample(10, random: gen1))
    assert_equal([], ary)
    ary = (0...10000).to_a
    assert_equal([5000, 0, 5001, 2, 5002, 4, 5003, 6, 5004, 8, 5005], ary.sample(11, random: gen0))
    ary.sample(11, random: gen1) # implementation detail, may change in the future
    assert_equal([], ary)
  end

  def test_sample_random_generator_half
    half = Object.new
    def half.to_int
      5000
    end
    gen_to_int = proc do |max|
      half
    end
    class << gen_to_int
      alias rand call
    end
    ary = (0...10000).to_a
    assert_equal(5000, ary.sample(random: gen_to_int))
  end

  def test_sample_random_invalid_generator
    ary = (0..10).to_a
    assert_raise(NoMethodError) {
      ary.sample(random: Object.new)
    }
  end

  def test_cycle
    a = []
    [0, 1, 2].cycle do |i|
      a << i
      break if a.size == 10
    end
    assert_equal([0, 1, 2, 0, 1, 2, 0, 1, 2, 0], a)

    a = [0, 1, 2]
    assert_nil(a.cycle { a.clear })

    a = []
    [0, 1, 2].cycle(3) {|i| a << i }
    assert_equal([0, 1, 2, 0, 1, 2, 0, 1, 2], a)

    assert_equal(Float::INFINITY, a.cycle.size)
    assert_equal(27, a.cycle(3).size)
  end

  def test_reverse_each2
    a = [0, 1, 2, 3, 4, 5]
    r = []
    a.reverse_each do |x|
      r << x
      a.pop
      a.pop
    end
    assert_equal([5, 3, 1], r)
  end

  def test_combination2
    assert_equal(:called, (0..100).to_a.combination(50) { break :called }, "[ruby-core:29240] ... must be yielded even if 100C50 > signed integer")
  end

  def test_combination_clear
    bug9939 = '[ruby-core:63149] [Bug #9939]'
    assert_nothing_raised(bug9939) {
      a = [*0..100]
      a.combination(3) {|*,x| a.clear}
    }

    bug13052 = '[ruby-core:78738] [Bug #13052] Array#combination segfaults if the Array is modified during iteration'
    assert_nothing_raised(bug13052) {
      a = [*0..100]
      a.combination(1) { a.clear }
      a = [*0..100]
      a.repeated_combination(1) { a.clear }
    }
  end

  def test_product2
    a = (0..100).to_a
    assert_raise(RangeError) do
      a.product(a, a, a, a, a, a, a, a, a, a)
    end
    assert_nothing_raised(RangeError) do
      a.product(a, a, a, a, a, a, a, a, a, a) { break }
    end
  end

  def test_initialize2
    a = [1] * 1000
    a.instance_eval { initialize }
    assert_equal([], a)
  end

  def test_shift_shared_ary
    a = (1..100).to_a
    b = []
    b.replace(a)
    assert_equal((1..10).to_a, a.shift(10))
    assert_equal((11..100).to_a, a)

    a = (1..30).to_a
    assert_equal((1..3).to_a, a.shift(3))
    # occupied
    assert_equal((4..6).to_a, a.shift(3))
  end

  def test_replace_shared_ary
    a = [1] * 100
    b = []
    b.replace(a)
    a.replace([1, 2, 3])
    assert_equal([1, 2, 3], a)
    assert_equal([1] * 100, b)
  end

  def test_fill_negative_length
    a = (1..10).to_a
    a.fill(:foo, 5, -3)
    assert_equal((1..10).to_a, a)
  end

  def test_slice_frozen_array
    a = [1,2,3,4,5].freeze
    assert_equal([1,2,3,4], a[0,4])
    assert_equal([2,3,4,5], a[1,4])
  end

  def test_sort_by!
    a = [1,3,5,2,4]
    a.sort_by! {|x| -x }
    assert_equal([5,4,3,2,1], a)
  end

  def test_rotate
    a = [1,2,3,4,5].freeze
    assert_equal([2,3,4,5,1], a.rotate)
    assert_equal([5,1,2,3,4], a.rotate(-1))
    assert_equal([3,4,5,1,2], a.rotate(2))
    assert_equal([4,5,1,2,3], a.rotate(-2))
    assert_equal([4,5,1,2,3], a.rotate(13))
    assert_equal([3,4,5,1,2], a.rotate(-13))
    a = [1].freeze
    assert_equal([1], a.rotate)
    assert_equal([1], a.rotate(2))
    assert_equal([1], a.rotate(-4))
    assert_equal([1], a.rotate(13))
    assert_equal([1], a.rotate(-13))
    a = [].freeze
    assert_equal([], a.rotate)
    assert_equal([], a.rotate(2))
    assert_equal([], a.rotate(-4))
    assert_equal([], a.rotate(13))
    assert_equal([], a.rotate(-13))
    a = [1,2,3]
    assert_raise(ArgumentError) { a.rotate(1, 1) }
    assert_equal([1,2,3,4,5].rotate(2**31-1), [1,2,3,4,5].rotate(2**31-0.1))
    assert_equal([1,2,3,4,5].rotate(-2**31), [1,2,3,4,5].rotate(-2**31-0.9))
  end

  def test_rotate!
    a = [1,2,3,4,5]
    assert_equal([2,3,4,5,1], a.rotate!)
    assert_equal([2,3,4,5,1], a)
    assert_equal([4,5,1,2,3], a.rotate!(2))
    assert_equal([5,1,2,3,4], a.rotate!(-4))
    assert_equal([3,4,5,1,2], a.rotate!(13))
    assert_equal([5,1,2,3,4], a.rotate!(-13))
    a = [1]
    assert_equal([1], a.rotate!)
    assert_equal([1], a.rotate!(2))
    assert_equal([1], a.rotate!(-4))
    assert_equal([1], a.rotate!(13))
    assert_equal([1], a.rotate!(-13))
    a = []
    assert_equal([], a.rotate!)
    assert_equal([], a.rotate!(2))
    assert_equal([], a.rotate!(-4))
    assert_equal([], a.rotate!(13))
    assert_equal([], a.rotate!(-13))
    a = [].freeze
    assert_raise_with_message(FrozenError, /can\'t modify frozen/) {a.rotate!}
    a = [1,2,3]
    assert_raise(ArgumentError) { a.rotate!(1, 1) }
  end

  def test_bsearch_typechecks_return_values
    assert_raise(TypeError) do
      [1, 2, 42, 100, 666].bsearch{ "not ok" }
    end
    c = eval("class C\u{309a 26a1 26c4 1f300};self;end")
    assert_raise_with_message(TypeError, /C\u{309a 26a1 26c4 1f300}/) do
      [0,1].bsearch {c.new}
    end
    assert_equal [1, 2, 42, 100, 666].bsearch{}, [1, 2, 42, 100, 666].bsearch{false}
  end

  def test_bsearch_with_no_block
    enum = [1, 2, 42, 100, 666].bsearch
    assert_nil enum.size
    assert_equal 42, enum.each{|x| x >= 33 }
  end

  def test_bsearch_in_find_minimum_mode
    a = [0, 4, 7, 10, 12]
    assert_equal(4, a.bsearch {|x| x >=   4 })
    assert_equal(7, a.bsearch {|x| x >=   6 })
    assert_equal(0, a.bsearch {|x| x >=  -1 })
    assert_equal(nil, a.bsearch {|x| x >= 100 })
  end

  def test_bsearch_in_find_any_mode
    a = [0, 4, 7, 10, 12]
    assert_include([4, 7], a.bsearch {|x| 1 - x / 4 })
    assert_equal(nil, a.bsearch {|x| 4 - x / 2 })
    assert_equal(nil, a.bsearch {|x| 1 })
    assert_equal(nil, a.bsearch {|x| -1 })

    assert_include([4, 7], a.bsearch {|x| (1 - x / 4) * (2**100) })
    assert_equal(nil, a.bsearch {|x|   1  * (2**100) })
    assert_equal(nil, a.bsearch {|x| (-1) * (2**100) })

    assert_equal(4, a.bsearch {|x| (4 - x).to_r })

    assert_include([4, 7], a.bsearch {|x| (2**100).coerce((1 - x / 4) * (2**100)).first })
  end

  def test_bsearch_index_typechecks_return_values
    assert_raise(TypeError) do
      [1, 2, 42, 100, 666].bsearch_index {"not ok"}
    end
    assert_equal [1, 2, 42, 100, 666].bsearch_index {}, [1, 2, 42, 100, 666].bsearch_index {false}
  end

  def test_bsearch_index_with_no_block
    enum = [1, 2, 42, 100, 666].bsearch_index
    assert_nil enum.size
    assert_equal 2, enum.each{|x| x >= 33 }
  end

  def test_bsearch_index_in_find_minimum_mode
    a = [0, 4, 7, 10, 12]
    assert_equal(1, a.bsearch_index {|x| x >=   4 })
    assert_equal(2, a.bsearch_index {|x| x >=   6 })
    assert_equal(0, a.bsearch_index {|x| x >=  -1 })
    assert_equal(nil, a.bsearch_index {|x| x >= 100 })
  end

  def test_bsearch_index_in_find_any_mode
    a = [0, 4, 7, 10, 12]
    assert_include([1, 2], a.bsearch_index {|x| 1 - x / 4 })
    assert_equal(nil, a.bsearch_index {|x| 4 - x / 2 })
    assert_equal(nil, a.bsearch_index {|x| 1 })
    assert_equal(nil, a.bsearch_index {|x| -1 })

    assert_include([1, 2], a.bsearch_index {|x| (1 - x / 4) * (2**100) })
    assert_equal(nil, a.bsearch_index {|x|   1  * (2**100) })
    assert_equal(nil, a.bsearch_index {|x| (-1) * (2**100) })

    assert_equal(1, a.bsearch_index {|x| (4 - x).to_r })

    assert_include([1, 2], a.bsearch_index {|x| (2**100).coerce((1 - x / 4) * (2**100)).first })
  end

  def test_shared_marking
    reduce = proc do |s|
      s.gsub(/(verify_internal_consistency_reachable_i:\sWB\smiss\s\S+\s\(T_ARRAY\)\s->\s)\S+\s\((proc|T_NONE)\)\n
             \K(?:\1\S+\s\(\2\)\n)*/x) do
        "...(snip #{$&.count("\n")} lines)...\n"
      end
    end
    begin
      assert_normal_exit(<<-EOS, '[Bug #9718]', timeout: 5, stdout_filter: reduce)
      queue = []
      50.times do
        10_000.times do
          queue << lambda{}
        end
        GC.start(full_mark: false, immediate_sweep: true)
        GC.verify_internal_consistency
        queue.shift.call
      end
    EOS
    rescue Timeout::Error => e
      omit e.message
    end
  end

  sizeof_long = [0].pack("l!").size
  sizeof_voidp = [""].pack("p").size
  if sizeof_long < sizeof_voidp
    ARY_MAX = (1<<(8*sizeof_long-1)) / sizeof_voidp - 1
    Bug11235 = '[ruby-dev:49043] [Bug #11235]'

    def test_push_over_ary_max
      assert_separately(['-', ARY_MAX.to_s, Bug11235], "#{<<~"begin;"}\n#{<<~'end;'}", timeout: 120)
      begin;
        a = Array.new(ARGV[0].to_i)
        assert_raise(IndexError, ARGV[1]) {0x1000.times {a.push(1)}}
      end;
    end

    def test_unshift_over_ary_max
      assert_separately(['-', ARY_MAX.to_s, Bug11235], "#{<<~"begin;"}\n#{<<~'end;'}")
      begin;
        a = Array.new(ARGV[0].to_i)
        assert_raise(IndexError, ARGV[1]) {0x1000.times {a.unshift(1)}}
      end;
    end

    def test_splice_over_ary_max
      assert_separately(['-', ARY_MAX.to_s, Bug11235], "#{<<~"begin;"}\n#{<<~'end;'}")
      begin;
        a = Array.new(ARGV[0].to_i)
        assert_raise(IndexError, ARGV[1]) {a[0, 0] = Array.new(0x1000)}
      end;
    end
  end

  def test_dig
    h = @cls[@cls[{a: 1}], 0]
    assert_equal(1, h.dig(0, 0, :a))
    assert_nil(h.dig(2, 0))
    assert_raise(TypeError) {h.dig(1, 0)}
  end

  FIXNUM_MIN = RbConfig::LIMITS['FIXNUM_MIN']
  FIXNUM_MAX = RbConfig::LIMITS['FIXNUM_MAX']

  def assert_typed_equal(e, v, cls, msg=nil)
    assert_kind_of(cls, v, msg)
    assert_equal(e, v, msg)
  end

  def assert_int_equal(e, v, msg=nil)
    assert_typed_equal(e, v, Integer, msg)
  end

  def assert_rational_equal(e, v, msg=nil)
    assert_typed_equal(e, v, Rational, msg)
  end

  def assert_float_equal(e, v, msg=nil)
    assert_typed_equal(e, v, Float, msg)
  end

  def assert_complex_equal(e, v, msg=nil)
    assert_typed_equal(e, v, Complex, msg)
  end

  def test_sum
    assert_int_equal(0, [].sum)
    assert_int_equal(3, [3].sum)
    assert_int_equal(8, [3, 5].sum)
    assert_int_equal(15, [3, 5, 7].sum)
    assert_rational_equal(8r, [3, 5r].sum)
    assert_float_equal(15.0, [3, 5, 7.0].sum)
    assert_float_equal(15.0, [3, 5r, 7.0].sum)
    assert_complex_equal(8r + 1i, [3, 5r, 1i].sum)
    assert_complex_equal(15.0 + 1i, [3, 5r, 7.0, 1i].sum)

    assert_int_equal(2*FIXNUM_MAX, Array.new(2, FIXNUM_MAX).sum)
    assert_int_equal(2*(FIXNUM_MAX+1), Array.new(2, FIXNUM_MAX+1).sum)
    assert_int_equal(10*FIXNUM_MAX, Array.new(10, FIXNUM_MAX).sum)
    assert_int_equal(0, ([FIXNUM_MAX, 1, -FIXNUM_MAX, -1]*10).sum)
    assert_int_equal(FIXNUM_MAX*10, ([FIXNUM_MAX+1, -1]*10).sum)
    assert_int_equal(2*FIXNUM_MIN, Array.new(2, FIXNUM_MIN).sum)

    assert_float_equal(0.0, [].sum(0.0))
    assert_float_equal(3.0, [3].sum(0.0))
    assert_float_equal(3.5, [3].sum(0.5))
    assert_float_equal(8.5, [3.5, 5].sum)
    assert_float_equal(10.5, [2, 8.5].sum)
    assert_float_equal((FIXNUM_MAX+1).to_f, [FIXNUM_MAX, 1, 0.0].sum)
    assert_float_equal((FIXNUM_MAX+1).to_f, [0.0, FIXNUM_MAX+1].sum)

    assert_rational_equal(3/2r, [1/2r, 1].sum)
    assert_rational_equal(5/6r, [1/2r, 1/3r].sum)

    assert_equal(2.0+3.0i, [2.0, 3.0i].sum)

    assert_int_equal(13, [1, 2].sum(10))
    assert_int_equal(16, [1, 2].sum(10) {|v| v * 2 })

    yielded = []
    three = SimpleDelegator.new(3)
    ary = [1, 2.0, three]
    assert_float_equal(12.0, ary.sum {|x| yielded << x; x * 2 })
    assert_equal(ary, yielded)

    assert_raise(TypeError) { [Object.new].sum }

    large_number = 100000000
    small_number = 1e-9
    until (large_number + small_number) == large_number
      small_number /= 10
    end
    assert_float_equal(large_number+(small_number*10), [large_number, *[small_number]*10].sum)
    assert_float_equal(large_number+(small_number*10), [large_number/1r, *[small_number]*10].sum)
    assert_float_equal(large_number+(small_number*11), [small_number, large_number/1r, *[small_number]*10].sum)
    assert_float_equal(small_number, [large_number, small_number, -large_number].sum)
    assert_equal(+Float::INFINITY, [+Float::INFINITY].sum)
    assert_equal(+Float::INFINITY, [0.0, +Float::INFINITY].sum)
    assert_equal(+Float::INFINITY, [+Float::INFINITY, 0.0].sum)
    assert_equal(-Float::INFINITY, [-Float::INFINITY].sum)
    assert_equal(-Float::INFINITY, [0.0, -Float::INFINITY].sum)
    assert_equal(-Float::INFINITY, [-Float::INFINITY, 0.0].sum)
    assert_predicate([-Float::INFINITY, Float::INFINITY].sum, :nan?)

    assert_equal("abc", ["a", "b", "c"].sum(""))
    assert_equal([1, [2], 3], [[1], [[2]], [3]].sum([]))

    assert_raise(TypeError) {[0].sum("")}
    assert_raise(TypeError) {[1].sum("")}
  end

  def test_big_array_literal_with_kwsplat
    lit = "["
    10000.times { lit << "{}," }
    lit << "**{}]"

    assert_equal(10000, eval(lit).size)
  end

  def test_array_safely_modified_by_sort_block
    var_0 = (1..70).to_a
    var_0.sort! do |var_0_block_129, var_1_block_129|
      var_0.pop
      var_1_block_129 <=> var_0_block_129
    end.shift(3)
    assert_equal((1..67).to_a.reverse, var_0)
  end

  private
  def need_continuation
    unless respond_to?(:callcc, true)
      EnvUtil.suppress_warning {require 'continuation'}
    end
  end
end

class TestArraySubclass < TestArray
  def setup
    @verbose = $VERBOSE
    @cls = Class.new(Array)
  end

  def test_to_a
    a = @cls[ 1, 2, 3 ]
    a_id = a.__id__
    assert_equal_instance([1, 2, 3], a.to_a)
    assert_not_equal(a_id, a.to_a.__id__)
  end

  def test_array_subclass
    assert_equal(Array, @cls[1,2,3].uniq.class, "[ruby-dev:34581]")
    assert_equal(Array, @cls[1,2][0,1].class) # embedded
    assert_equal(Array, @cls[*(1..100)][1..99].class) #not embedded
  end
end
