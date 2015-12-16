# frozen_string_literal: false
require 'test/unit'
require 'set'

class TC_Set < Test::Unit::TestCase
  class Set2 < Set
  end

  def test_aref
    assert_nothing_raised {
      Set[]
      Set[nil]
      Set[1,2,3]
    }

    assert_equal(0, Set[].size)
    assert_equal(1, Set[nil].size)
    assert_equal(1, Set[[]].size)
    assert_equal(1, Set[[nil]].size)

    set = Set[2,4,6,4]
    assert_equal(Set.new([2,4,6]), set)
  end

  def test_s_new
    assert_nothing_raised {
      Set.new()
      Set.new(nil)
      Set.new([])
      Set.new([1,2])
      Set.new('a'..'c')
    }
    assert_raise(ArgumentError) {
      Set.new(false)
    }
    assert_raise(ArgumentError) {
      Set.new(1)
    }
    assert_raise(ArgumentError) {
      Set.new(1,2)
    }

    assert_equal(0, Set.new().size)
    assert_equal(0, Set.new(nil).size)
    assert_equal(0, Set.new([]).size)
    assert_equal(1, Set.new([nil]).size)

    ary = [2,4,6,4]
    set = Set.new(ary)
    ary.clear
    assert_equal(false, set.empty?)
    assert_equal(3, set.size)

    ary = [1,2,3]

    s = Set.new(ary) { |o| o * 2 }
    assert_equal([2,4,6], s.sort)
  end

  def test_clone
    set1 = Set.new
    set2 = set1.clone
    set1 << 'abc'
    assert_equal(Set.new, set2)
  end

  def test_dup
    set1 = Set[1,2]
    set2 = set1.dup

    assert_not_same(set1, set2)

    assert_equal(set1, set2)

    set1.add(3)

    assert_not_equal(set1, set2)
  end

  def test_size
    assert_equal(0, Set[].size)
    assert_equal(2, Set[1,2].size)
    assert_equal(2, Set[1,2,1].size)
  end

  def test_empty?
    assert_equal(true, Set[].empty?)
    assert_equal(false, Set[1, 2].empty?)
  end

  def test_clear
    set = Set[1,2]
    ret = set.clear

    assert_same(set, ret)
    assert_equal(true, set.empty?)
  end

  def test_replace
    set = Set[1,2]
    ret = set.replace('a'..'c')

    assert_same(set, ret)
    assert_equal(Set['a','b','c'], set)

    set = Set[1,2]
    assert_raise(ArgumentError) {
      set.replace(3)
    }
    assert_equal(Set[1,2], set)
  end

  def test_to_a
    set = Set[1,2,3,2]
    ary = set.to_a

    assert_equal([1,2,3], ary.sort)
  end

  def test_flatten
    # test1
    set1 = Set[
      1,
      Set[
        5,
        Set[7,
          Set[0]
        ],
        Set[6,2],
        1
      ],
      3,
      Set[3,4]
    ]

    set2 = set1.flatten
    set3 = Set.new(0..7)

    assert_not_same(set2, set1)
    assert_equal(set3, set2)

    # test2; destructive
    orig_set1 = set1
    set1.flatten!

    assert_same(orig_set1, set1)
    assert_equal(set3, set1)

    # test3; multiple occurrences of a set in an set
    set1 = Set[1, 2]
    set2 = Set[set1, Set[set1, 4], 3]

    assert_nothing_raised {
      set2.flatten!
    }

    assert_equal(Set.new(1..4), set2)

    # test4; recursion
    set2 = Set[]
    set1 = Set[1, set2]
    set2.add(set1)

    assert_raise(ArgumentError) {
      set1.flatten!
    }

    # test5; miscellaneous
    empty = Set[]
    set =  Set[Set[empty, "a"],Set[empty, "b"]]

    assert_nothing_raised {
      set.flatten
    }

    set1 = empty.merge(Set["no_more", set])

    assert_nil(Set.new(0..31).flatten!)

    x = Set[Set[],Set[1,2]].flatten!
    y = Set[1,2]

    assert_equal(x, y)
  end

  def test_include?
    set = Set[1,2,3]

    assert_equal(true, set.include?(1))
    assert_equal(true, set.include?(2))
    assert_equal(true, set.include?(3))
    assert_equal(false, set.include?(0))
    assert_equal(false, set.include?(nil))

    set = Set["1",nil,"2",nil,"0","1",false]
    assert_equal(true, set.include?(nil))
    assert_equal(true, set.include?(false))
    assert_equal(true, set.include?("1"))
    assert_equal(false, set.include?(0))
    assert_equal(false, set.include?(true))
  end

  def test_superset?
    set = Set[1,2,3]

    assert_raise(ArgumentError) {
      set.superset?()
    }

    assert_raise(ArgumentError) {
      set.superset?(2)
    }

    assert_raise(ArgumentError) {
      set.superset?([2])
    }

    [Set, Set2].each { |klass|
      assert_equal(true, set.superset?(klass[]), klass.name)
      assert_equal(true, set.superset?(klass[1,2]), klass.name)
      assert_equal(true, set.superset?(klass[1,2,3]), klass.name)
      assert_equal(false, set.superset?(klass[1,2,3,4]), klass.name)
      assert_equal(false, set.superset?(klass[1,4]), klass.name)

      assert_equal(true, set >= klass[1,2,3], klass.name)
      assert_equal(true, set >= klass[1,2], klass.name)

      assert_equal(true, Set[].superset?(klass[]), klass.name)
    }
  end

  def test_proper_superset?
    set = Set[1,2,3]

    assert_raise(ArgumentError) {
      set.proper_superset?()
    }

    assert_raise(ArgumentError) {
      set.proper_superset?(2)
    }

    assert_raise(ArgumentError) {
      set.proper_superset?([2])
    }

    [Set, Set2].each { |klass|
      assert_equal(true, set.proper_superset?(klass[]), klass.name)
      assert_equal(true, set.proper_superset?(klass[1,2]), klass.name)
      assert_equal(false, set.proper_superset?(klass[1,2,3]), klass.name)
      assert_equal(false, set.proper_superset?(klass[1,2,3,4]), klass.name)
      assert_equal(false, set.proper_superset?(klass[1,4]), klass.name)

      assert_equal(false, set > klass[1,2,3], klass.name)
      assert_equal(true, set > klass[1,2], klass.name)

      assert_equal(false, Set[].proper_superset?(klass[]), klass.name)
    }
  end

  def test_subset?
    set = Set[1,2,3]

    assert_raise(ArgumentError) {
      set.subset?()
    }

    assert_raise(ArgumentError) {
      set.subset?(2)
    }

    assert_raise(ArgumentError) {
      set.subset?([2])
    }

    [Set, Set2].each { |klass|
      assert_equal(true, set.subset?(klass[1,2,3,4]), klass.name)
      assert_equal(true, set.subset?(klass[1,2,3]), klass.name)
      assert_equal(false, set.subset?(klass[1,2]), klass.name)
      assert_equal(false, set.subset?(klass[]), klass.name)

      assert_equal(true, set <= klass[1,2,3], klass.name)
      assert_equal(true, set <= klass[1,2,3,4], klass.name)

      assert_equal(true, Set[].subset?(klass[1]), klass.name)
      assert_equal(true, Set[].subset?(klass[]), klass.name)
    }
  end

  def test_proper_subset?
    set = Set[1,2,3]

    assert_raise(ArgumentError) {
      set.proper_subset?()
    }

    assert_raise(ArgumentError) {
      set.proper_subset?(2)
    }

    assert_raise(ArgumentError) {
      set.proper_subset?([2])
    }

    [Set, Set2].each { |klass|
      assert_equal(true, set.proper_subset?(klass[1,2,3,4]), klass.name)
      assert_equal(false, set.proper_subset?(klass[1,2,3]), klass.name)
      assert_equal(false, set.proper_subset?(klass[1,2]), klass.name)
      assert_equal(false, set.proper_subset?(klass[]), klass.name)

      assert_equal(false, set < klass[1,2,3], klass.name)
      assert_equal(true, set < klass[1,2,3,4], klass.name)

      assert_equal(false, Set[].proper_subset?(klass[]), klass.name)
    }
  end

  def assert_intersect(expected, set, other)
    case expected
    when true
      assert_send([set, :intersect?, other])
      assert_send([other, :intersect?, set])
      assert_not_send([set, :disjoint?, other])
      assert_not_send([other, :disjoint?, set])
    when false
      assert_not_send([set, :intersect?, other])
      assert_not_send([other, :intersect?, set])
      assert_send([set, :disjoint?, other])
      assert_send([other, :disjoint?, set])
    when Class
      assert_raise(expected) {
        set.intersect?(other)
      }
      assert_raise(expected) {
        set.disjoint?(other)
      }
    else
      raise ArgumentError, "%s: unsupported expected value: %s" % [__method__, expected.inspect]
    end
  end

  def test_intersect?
    set = Set[3,4,5]

    assert_intersect(ArgumentError, set, 3)
    assert_intersect(ArgumentError, set, [2,4,6])

    assert_intersect(true, set, set)
    assert_intersect(true, set, Set[2,4])
    assert_intersect(true, set, Set[5,6,7])
    assert_intersect(true, set, Set[1,2,6,8,4])

    assert_intersect(false, set, Set[])
    assert_intersect(false, set, Set[0,2])
    assert_intersect(false, set, Set[0,2,6])
    assert_intersect(false, set, Set[0,2,6,8,10])

    # Make sure set hasn't changed
    assert_equal(Set[3,4,5], set)
  end

  def test_each
    ary = [1,3,5,7,10,20]
    set = Set.new(ary)

    ret = set.each { |o| }
    assert_same(set, ret)

    e = set.each
    assert_instance_of(Enumerator, e)

    assert_nothing_raised {
      set.each { |o|
        ary.delete(o) or raise "unexpected element: #{o}"
      }

      ary.empty? or raise "forgotten elements: #{ary.join(', ')}"
    }

    assert_equal(6, e.size)
    set << 42
    assert_equal(7, e.size)
  end

  def test_add
    set = Set[1,2,3]

    ret = set.add(2)
    assert_same(set, ret)
    assert_equal(Set[1,2,3], set)

    ret = set.add?(2)
    assert_nil(ret)
    assert_equal(Set[1,2,3], set)

    ret = set.add(4)
    assert_same(set, ret)
    assert_equal(Set[1,2,3,4], set)

    ret = set.add?(5)
    assert_same(set, ret)
    assert_equal(Set[1,2,3,4,5], set)
  end

  def test_delete
    set = Set[1,2,3]

    ret = set.delete(4)
    assert_same(set, ret)
    assert_equal(Set[1,2,3], set)

    ret = set.delete?(4)
    assert_nil(ret)
    assert_equal(Set[1,2,3], set)

    ret = set.delete(2)
    assert_equal(set, ret)
    assert_equal(Set[1,3], set)

    ret = set.delete?(1)
    assert_equal(set, ret)
    assert_equal(Set[3], set)
  end

  def test_delete_if
    set = Set.new(1..10)
    ret = set.delete_if { |i| i > 10 }
    assert_same(set, ret)
    assert_equal(Set.new(1..10), set)

    set = Set.new(1..10)
    ret = set.delete_if { |i| i % 3 == 0 }
    assert_same(set, ret)
    assert_equal(Set[1,2,4,5,7,8,10], set)
  end

  def test_keep_if
    set = Set.new(1..10)
    ret = set.keep_if { |i| i <= 10 }
    assert_same(set, ret)
    assert_equal(Set.new(1..10), set)

    set = Set.new(1..10)
    ret = set.keep_if { |i| i % 3 != 0 }
    assert_same(set, ret)
    assert_equal(Set[1,2,4,5,7,8,10], set)
  end

  def test_collect!
    set = Set[1,2,3,'a','b','c',-1..1,2..4]

    ret = set.collect! { |i|
      case i
      when Numeric
        i * 2
      when String
        i.upcase
      else
        nil
      end
    }

    assert_same(set, ret)
    assert_equal(Set[2,4,6,'A','B','C',nil], set)
  end

  def test_reject!
    set = Set.new(1..10)

    ret = set.reject! { |i| i > 10 }
    assert_nil(ret)
    assert_equal(Set.new(1..10), set)

    ret = set.reject! { |i| i % 3 == 0 }
    assert_same(set, ret)
    assert_equal(Set[1,2,4,5,7,8,10], set)
  end

  def test_merge
    set = Set[1,2,3]

    ret = set.merge([2,4,6])
    assert_same(set, ret)
    assert_equal(Set[1,2,3,4,6], set)
  end

  def test_subtract
    set = Set[1,2,3]

    ret = set.subtract([2,4,6])
    assert_same(set, ret)
    assert_equal(Set[1,3], set)
  end

  def test_plus
    set = Set[1,2,3]

    ret = set + [2,4,6]
    assert_not_same(set, ret)
    assert_equal(Set[1,2,3,4,6], ret)
  end

  def test_minus
    set = Set[1,2,3]

    ret = set - [2,4,6]
    assert_not_same(set, ret)
    assert_equal(Set[1,3], ret)
  end

  def test_and
    set = Set[1,2,3,4]

    ret = set & [2,4,6]
    assert_not_same(set, ret)
    assert_equal(Set[2,4], ret)
  end

  def test_xor
    set = Set[1,2,3,4]
    ret = set ^ [2,4,5,5]
    assert_not_same(set, ret)
    assert_equal(Set[1,3,5], ret)
  end

  def test_eq
    set1 = Set[2,3,1]
    set2 = Set[1,2,3]

    assert_equal(set1, set1)
    assert_equal(set1, set2)
    assert_not_equal(Set[1], [1])

    set1 = Class.new(Set)["a", "b"]
    set2 = Set["a", "b", set1]
    set1 = set1.add(set1.clone)

    assert_equal(set2, set2.clone)
    assert_equal(set1.clone, set1)

    assert_not_equal(Set[Exception.new,nil], Set[Exception.new,Exception.new], "[ruby-dev:26127]")
  end

  def test_classify
    set = Set.new(1..10)
    ret = set.classify { |i| i % 3 }

    assert_equal(3, ret.size)
    assert_instance_of(Hash, ret)
    ret.each_value { |value| assert_instance_of(Set, value) }
    assert_equal(Set[3,6,9], ret[0])
    assert_equal(Set[1,4,7,10], ret[1])
    assert_equal(Set[2,5,8], ret[2])
  end

  def test_divide
    set = Set.new(1..10)
    ret = set.divide { |i| i % 3 }

    assert_equal(3, ret.size)
    n = 0
    ret.each { |s| n += s.size }
    assert_equal(set.size, n)
    assert_equal(set, ret.flatten)

    set = Set[7,10,5,11,1,3,4,9,0]
    ret = set.divide { |a,b| (a - b).abs == 1 }

    assert_equal(4, ret.size)
    n = 0
    ret.each { |s| n += s.size }
    assert_equal(set.size, n)
    assert_equal(set, ret.flatten)
    ret.each { |s|
      if s.include?(0)
        assert_equal(Set[0,1], s)
      elsif s.include?(3)
        assert_equal(Set[3,4,5], s)
      elsif s.include?(7)
        assert_equal(Set[7], s)
      elsif s.include?(9)
        assert_equal(Set[9,10,11], s)
      else
        raise "unexpected group: #{s.inspect}"
      end
    }
  end

  def test_taintness
    orig = set = Set[1,2,3]
    assert_equal false, set.tainted?
    assert_same orig, set.taint
    assert_equal true, set.tainted?
    assert_same orig, set.untaint
    assert_equal false, set.tainted?
  end

  def test_freeze
    orig = set = Set[1,2,3]
    assert_equal false, set.frozen?
    set << 4
    assert_same orig, set.freeze
    assert_equal true, set.frozen?
    assert_raise(RuntimeError) {
      set << 5
    }
    assert_equal 4, set.size
  end

  def test_freeze_dup
    set1 = Set[1,2,3]
    set1.freeze
    set2 = set1.dup

    assert_not_predicate set2, :frozen?
    assert_nothing_raised {
      set2.add 4
    }
  end

  def test_freeze_clone
    set1 = Set[1,2,3]
    set1.freeze
    set2 = set1.clone

    assert_predicate set2, :frozen?
    assert_raise(RuntimeError) {
      set2.add 5
    }
  end

  def test_inspect
    set1 = Set[1]

    assert_equal('#<Set: {1}>', set1.inspect)

    set2 = Set[Set[0], 1, 2, set1]
    assert_equal(false, set2.inspect.include?('#<Set: {...}>'))

    set1.add(set2)
    assert_equal(true, set1.inspect.include?('#<Set: {...}>'))
  end
end

class TC_SortedSet < Test::Unit::TestCase
  def test_sortedset
    s = SortedSet[4,5,3,1,2]

    assert_equal([1,2,3,4,5], s.to_a)

    prev = nil
    s.each { |o| assert(prev < o) if prev; prev = o }
    assert_not_nil(prev)

    s.map! { |o| -2 * o }

    assert_equal([-10,-8,-6,-4,-2], s.to_a)

    prev = nil
    ret = s.each { |o| assert(prev < o) if prev; prev = o }
    assert_not_nil(prev)
    assert_same(s, ret)

    s = SortedSet.new([2,1,3]) { |o| o * -2 }
    assert_equal([-6,-4,-2], s.to_a)

    s = SortedSet.new(['one', 'two', 'three', 'four'])
    a = []
    ret = s.delete_if { |o| a << o; o.start_with?('t') }
    assert_same(s, ret)
    assert_equal(['four', 'one'], s.to_a)
    assert_equal(['four', 'one', 'three', 'two'], a)

    s = SortedSet.new(['one', 'two', 'three', 'four'])
    a = []
    ret = s.reject! { |o| a << o; o.start_with?('t') }
    assert_same(s, ret)
    assert_equal(['four', 'one'], s.to_a)
    assert_equal(['four', 'one', 'three', 'two'], a)

    s = SortedSet.new(['one', 'two', 'three', 'four'])
    a = []
    ret = s.reject! { |o| a << o; false }
    assert_same(nil, ret)
    assert_equal(['four', 'one', 'three', 'two'], s.to_a)
    assert_equal(['four', 'one', 'three', 'two'], a)
  end

  def test_each
    ary = [1,3,5,7,10,20]
    set = SortedSet.new(ary)

    ret = set.each { |o| }
    assert_same(set, ret)

    e = set.each
    assert_instance_of(Enumerator, e)

    assert_nothing_raised {
      set.each { |o|
        ary.delete(o) or raise "unexpected element: #{o}"
      }

      ary.empty? or raise "forgotten elements: #{ary.join(', ')}"
    }

    assert_equal(6, e.size)
    set << 42
    assert_equal(7, e.size)
  end
end

class TC_Enumerable < Test::Unit::TestCase
  def test_to_set
    ary = [2,5,4,3,2,1,3]

    set = ary.to_set
    assert_instance_of(Set, set)
    assert_equal([1,2,3,4,5], set.sort)

    set = ary.to_set { |o| o * -2 }
    assert_instance_of(Set, set)
    assert_equal([-10,-8,-6,-4,-2], set.sort)

    assert_same set, set.to_set
    assert_not_same set, set.to_set { |o| o }

    set = ary.to_set(SortedSet)
    assert_instance_of(SortedSet, set)
    assert_equal([1,2,3,4,5], set.to_a)

    set = ary.to_set(SortedSet) { |o| o * -2 }
    assert_instance_of(SortedSet, set)
    assert_equal([-10,-8,-6,-4,-2], set.sort)
  end
end
