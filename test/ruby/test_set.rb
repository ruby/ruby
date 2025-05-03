# frozen_string_literal: false
require 'test/unit'
require 'set'

class TC_Set < Test::Unit::TestCase
  class Set2 < Set
  end

  def test_marshal
    set = Set[1, 2, 3]
    mset = Marshal.load(Marshal.dump(set))
    assert_equal(set, mset)
    assert_equal(set.compare_by_identity?, mset.compare_by_identity?)

    set.compare_by_identity
    mset = Marshal.load(Marshal.dump(set))
    assert_equal(set, mset)
    assert_equal(set.compare_by_identity?, mset.compare_by_identity?)

    set.instance_variable_set(:@a, 1)
    mset = Marshal.load(Marshal.dump(set))
    assert_equal(set, mset)
    assert_equal(set.compare_by_identity?, mset.compare_by_identity?)
    assert_equal(1, mset.instance_variable_get(:@a))

    old_stdlib_set_data = "\x04\bo:\bSet\x06:\n@hash}\bi\x06Ti\aTi\bTF".b
    set = Marshal.load(old_stdlib_set_data)
    assert_equal(Set[1, 2, 3], set)

    old_stdlib_set_cbi_data = "\x04\bo:\bSet\x06:\n@hashC:\tHash}\ai\x06Ti\aTF".b
    set = Marshal.load(old_stdlib_set_cbi_data)
    assert_equal(Set[1, 2].compare_by_identity, set)
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

  def test_to_h
    set = Set[1,2]
    assert_equal({1 => true, 2 => true}, set.to_h)
    assert_equal({1 => false, 2 => false}, set.to_h { [it, false] })
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

  def test_eqq
    set = Set[1,2,3]

    assert_equal(true, set === 1)
    assert_equal(true, set === 2)
    assert_equal(true, set === 3)
    assert_equal(false, set === 0)
    assert_equal(false, set === nil)

    set = Set["1",nil,"2",nil,"0","1",false]
    assert_equal(true, set === nil)
    assert_equal(true, set === false)
    assert_equal(true, set === "1")
    assert_equal(false, set === 0)
    assert_equal(false, set === true)
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

  def test_spacecraft_operator
    set = Set[1,2,3]

    assert_nil(set <=> 2)

    assert_nil(set <=> set.to_a)

    [Set, Set2].each { |klass|
      assert_equal(-1,  set <=> klass[1,2,3,4], klass.name)
      assert_equal( 0,  set <=> klass[3,2,1]  , klass.name)
      assert_equal(nil, set <=> klass[1,2,4]  , klass.name)
      assert_equal(+1,  set <=> klass[2,3]    , klass.name)
      assert_equal(+1,  set <=> klass[]       , klass.name)

      assert_equal(0, Set[] <=> klass[], klass.name)
    }
  end

  def assert_intersect(expected, set, other)
    case expected
    when true
      assert_send([set, :intersect?, other])
      assert_send([set, :intersect?, other.to_a])
      assert_send([other, :intersect?, set])
      assert_not_send([set, :disjoint?, other])
      assert_not_send([set, :disjoint?, other.to_a])
      assert_not_send([other, :disjoint?, set])
    when false
      assert_not_send([set, :intersect?, other])
      assert_not_send([set, :intersect?, other.to_a])
      assert_not_send([other, :intersect?, set])
      assert_send([set, :disjoint?, other])
      assert_send([set, :disjoint?, other.to_a])
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
    assert_intersect(true, set, Set[2,4,6])

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

    set = Set.new(1..10)
    enum = set.delete_if
    assert_equal(set.size, enum.size)
    assert_same(set, enum.each { |i| i % 3 == 0 })
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

    set = Set.new(1..10)
    enum = set.keep_if
    assert_equal(set.size, enum.size)
    assert_same(set, enum.each { |i| i % 3 != 0 })
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

    set = Set[1,2,3,'a','b','c',-1..1,2..4]
    enum = set.collect!

    assert_equal(set.size, enum.size)
    assert_same(set, enum.each  { |i|
      case i
      when Numeric
        i * 2
      when String
        i.upcase
      else
        nil
      end
    })
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

    set = Set.new(1..10)
    enum = set.reject!
    assert_equal(set.size, enum.size)
    assert_same(set, enum.each { |i| i % 3 == 0 })
    assert_equal(Set[1,2,4,5,7,8,10], set)
  end

  def test_select!
    set = Set.new(1..10)
    ret = set.select! { |i| i <= 10 }
    assert_equal(nil, ret)
    assert_equal(Set.new(1..10), set)

    set = Set.new(1..10)
    ret = set.select! { |i| i % 3 != 0 }
    assert_same(set, ret)
    assert_equal(Set[1,2,4,5,7,8,10], set)

    set = Set.new(1..10)
    enum = set.select!
    assert_equal(set.size, enum.size)
    assert_equal(nil, enum.each { |i| i <= 10 })
    assert_equal(Set.new(1..10), set)
  end

  def test_filter!
    set = Set.new(1..10)
    ret = set.filter! { |i| i <= 10 }
    assert_equal(nil, ret)
    assert_equal(Set.new(1..10), set)

    set = Set.new(1..10)
    ret = set.filter! { |i| i % 3 != 0 }
    assert_same(set, ret)
    assert_equal(Set[1,2,4,5,7,8,10], set)

    set = Set.new(1..10)
    enum = set.filter!
    assert_equal(set.size, enum.size)
    assert_equal(nil, enum.each { |i| i <= 10 })
    assert_equal(Set.new(1..10), set)
  end

  def test_merge
    set = Set[1,2,3]
    ret = set.merge([2,4,6])
    assert_same(set, ret)
    assert_equal(Set[1,2,3,4,6], set)

    set = Set[1,2,3]
    ret = set.merge()
    assert_same(set, ret)
    assert_equal(Set[1,2,3], set)

    set = Set[1,2,3]
    ret = set.merge([2,4,6], Set[4,5,6])
    assert_same(set, ret)
    assert_equal(Set[1,2,3,4,5,6], set)

    assert_raise(ArgumentError) {
      Set[].merge(a: 1)
    }
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

    set2 = Set2[1,2,3,4]
    ret2 = set2 ^ [2,4,5,5]
    assert_instance_of(Set2, ret2)
    assert_equal(Set2[1,3,5], ret2)
  end

  def test_eq
    set1 = Set[2,3,1]
    set2 = Set[1,2,3]

    assert_equal(set1, set1)
    assert_equal(set1, set2)
    assert_not_equal(Set[1], [1])

    set1 = Class.new(Set)["a", "b"]
    set1.add(set1).reset # Make recursive
    set2 = Set["a", "b", Set["a", "b", set1]]

    assert_equal(set1, set2)

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

    set = Set.new(1..10)
    enum = set.classify

    assert_equal(set.size, enum.size)
    ret = enum.each { |i| i % 3 }
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

    set = Set.new(1..10)
    enum = set.divide
    ret = enum.each { |i| i % 3 }

    assert_equal(set.size, enum.size)
    assert_equal(3, ret.size)
    n = 0
    ret.each { |s| n += s.size }
    assert_equal(set.size, n)
    assert_equal(set, ret.flatten)
  end

  def test_freeze
    orig = set = Set[1,2,3]
    assert_equal false, set.frozen?
    set << 4
    assert_same orig, set.freeze
    assert_equal true, set.frozen?
    assert_raise(FrozenError) {
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
    assert_raise(FrozenError) {
      set2.add 5
    }
  end

  def test_freeze_clone_false
    set1 = Set[1,2,3]
    set1.freeze
    set2 = set1.clone(freeze: false)

    assert_not_predicate set2, :frozen?
    set2.add 5
    assert_equal Set[1,2,3,5], set2
    assert_equal Set[1,2,3], set1
  end if Kernel.instance_method(:initialize_clone).arity != 1

  def test_join
    assert_equal('123', Set[1, 2, 3].join)
    assert_equal('1 & 2 & 3', Set[1, 2, 3].join(' & '))
  end

  def test_inspect
    set1 = Set[1, 2]
    assert_equal('#<Set: {1, 2}>', set1.inspect)

    set2 = Set[Set[0], 1, 2, set1]
    assert_equal('#<Set: {#<Set: {0}>, 1, 2, #<Set: {1, 2}>}>', set2.inspect)

    set1.add(set2)
    assert_equal('#<Set: {#<Set: {0}>, 1, 2, #<Set: {1, 2, #<Set: {...}>}>}>', set2.inspect)
  end

  def test_to_s
    set1 = Set[1, 2]
    assert_equal('#<Set: {1, 2}>', set1.to_s)

    set2 = Set[Set[0], 1, 2, set1]
    assert_equal('#<Set: {#<Set: {0}>, 1, 2, #<Set: {1, 2}>}>', set2.to_s)

    set1.add(set2)
    assert_equal('#<Set: {#<Set: {0}>, 1, 2, #<Set: {1, 2, #<Set: {...}>}>}>', set2.to_s)
  end

  def test_compare_by_identity
    a1, a2 = "a", "a"
    b1, b2 = "b", "b"
    c = "c"
    array = [a1, b1, c, a2, b2]

    iset = Set.new.compare_by_identity
    assert_send([iset, :compare_by_identity?])
    iset.merge(array)
    assert_equal(5, iset.size)
    assert_equal(array.map(&:object_id).sort, iset.map(&:object_id).sort)

    set = Set.new
    assert_not_send([set, :compare_by_identity?])
    set.merge(array)
    assert_equal(3, set.size)
    assert_equal(array.uniq.sort, set.sort)
  end

  def test_reset
    [Set, Class.new(Set)].each { |klass|
      a = [1, 2]
      b = [1]
      set = klass.new([a, b])

      b << 2
      set.reset

      assert_equal(klass.new([a]), set, klass.name)
    }
  end

  def test_set_gc_compact_does_not_allocate
    assert_in_out_err([], <<-"end;", [], [])
    def x
      s = Set.new
      s << Object.new
      s
    end

    x
    begin
      GC.compact
    rescue NotImplementedError
    end
    end;
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
  end
end

class TC_Set_Builtin < Test::Unit::TestCase
  private def should_omit?
    (RUBY_VERSION.scan(/\d+/).map(&:to_i) <=> [3, 2]) < 0 ||
      !File.exist?(File.expand_path('../prelude.rb', __dir__))
  end

  def test_Set
    omit "skipping the test for the builtin Set" if should_omit?

    assert_separately([], "#{<<~"begin;"}\n#{<<~'end;'}")
    begin;
      assert_nothing_raised do
        set = Set.new([1, 2])
        assert_equal('Set', set.class.name)
      end
    end;

    assert_separately([], "#{<<~"begin;"}\n#{<<~'end;'}")
    begin;
      assert_nothing_raised do
        set = Set[1, 2]
        assert_equal('Set', set.class.name)
      end
    end;
  end

  def test_to_set
    omit "skipping the test for the builtin Enumerable#to_set" if should_omit?

    assert_separately([], "#{<<~"begin;"}\n#{<<~'end;'}")
    begin;
      assert_nothing_raised do
        set = [1, 2].to_set
        assert_equal('Set', set.class.name)
      end
    end;
  end
end
