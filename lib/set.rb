#!/usr/bin/env ruby
#
# set - defines the Set class
#
# Copyright (c) 2002 Akinori MUSHA <knu@iDaemons.org>
#
# All rights reserved.
#
# You can redistribute and/or modify it under the same terms as Ruby.
#

=begin
= set.rb

This library provides the Set class that deals with a collection of
unordered values with no duplicates.  It is a hybrid of Array's
intuitive inter-operation facilities and Hash's fast lookup.

== Example

  require 'set'

  set1 = Set.new ["foo", "bar", "baz"]

  p set1			#=> #<Set: {"baz", "foo", "bar"}>

  p set1.include?("bar")	#=> true

  set1.add("heh")
  set1.delete("foo")

  p set1			#=> #<Set: {"heh", "baz", "bar"}>

== Set class
Set implements a collection of unordered values with no duplicates.
This is a hybrid of Array's intuitive inter-operation facilities and
Hash's fast lookup.

The equality of each couple of elements is determined according to
Object#eql? and Object#hash, since Set uses Hash as storage.

=== Included Modules
    Enumerable

=== Class Methods
--- Set::new(enum = nil)
    Creates a new set containing the elements of the given enumerable
    object.

--- Set[*ary]
    Creates a new set containing the given objects.

=== Instance Methods
--- dup
    Duplicates the set.

--- size
--- length
    Returns the number of elements.

--- empty?
    Returns true if the set contains no elements.

--- clear
    Removes all elements and returns self.

--- replace(enum)
    Replaces the contents of the set with the contents of the given
    enumerable object and returns self.

--- flatten
    Returns a new set that is a copy of the set, flattening each
    containing set recursively.

--- flatten!
    Equivalent to Set#flatten, but replaces the receiver with the
    result in place.  Returns nil if no modifications were made.

--- to_a
    Converts the set to an array. (the order is uncertain)

--- include?(o)
--- member?(o)
    Returns true if the set contains the given object.

--- contain?(enum)
    Returns true if the set contains every element of the given
    enumerable object.

--- each { |o| ... }
    Calls the given block once for each element in the set, passing
    the element as parameter.

--- add(o)
--- << o
    Adds the given object to the set and returns self.

--- delete(o)
    Deletes the given object from the set and returns the object.  If
    the object is not found, returns nil.

--- delete_if { |o| ... }
    Deletes every element of the set for which block evaluates to
    true, and returns self.

--- reject! { |o| ... }
    Equivalent to Set#delete_if, but returns nil if no changes were
    made.

--- merge(enum)
    Merges the elements of the given enumerable object to the set and
    returns self.

--- subtract(enum)
    Deletes every element that appears in the given enumerable object
    and returns self.

--- + enum
--- | enum
    Returns a new set built by merging the set and the elements of the
    given enumerable object.

--- - enum
    Returns a new set built by duplicating the set, removing every
    element that appear in the given enumerable object.

--- & enum
    Returns a new array containing elements common to the set and the
    given enumerable object.

--- ^ enum
    Returns a new array containing elements exclusive between the set
    and the given enumerable object.  (set ^ enum) is equivalent to
    ((set | enum) - (set & enum)).

--- == set
    Returns true if two sets are equal.  The equality of each couple
    of elements is defined according to Object#eql?.

--- classify { |o| ... }
    Classifies the set by the return value of the given block and
    returns a hash of {value => set of elements} pairs.  The block is
    called once for each element of the set, passing the element as
    parameter.

    e.g.:

      require 'set'
      files = Set.new(Dir.glob("*.rb"))
      hash = files.classify { |f| File.mtime(f).year }
      p hash    #=> {2000=>#<Set: {"a.rb", "b.rb"}>,
                #    2001=>#<Set: {"c.rb", "d.rb", "e.rb"}>,
                #    2002=>#<Set: {"f.rb"}>}

--- divide { |o| ... }
--- divide { |o1, o2| ... }

    Divides the set into a set of subsets according to the commonality
    defined by the given block.

    If the arity of the block is 2, elements o1 and o2 are in common
    if block.call(o1, o2) is true.  Otherwise, elements o1 and o2 are
    in common if block.call(o1) == block.call(o2).

    e.g.:

      require 'set'
      numbers = Set[1, 3, 4, 6, 9, 10, 11]
      set = numbers.divide { |i,j| (i - j).abs == 1 }
      p set     #=> #<Set: {#<Set: {1}>,
                #           #<Set: {11, 9, 10}>,
                #           #<Set: {3, 4}>,
                #           #<Set: {6}>}>

--- inspect
    Returns a string containing a human-readable representation of the
    set. ("#<Set: {element1, element2, ...}>")

=end

class Set
  include Enumerable

  def self.[](*ary)
    new(ary)
  end

  def initialize(enum = nil)
    @hash = {}

    enum.nil? and return

    enum.is_a?(Enumerable) or raise ArgumentError, "value must be enumerable"
    enum.each { |o| @hash[o] = true } 
  end

  def dup
    n = type.new
    @hash.each_key { |o| n.add(o) }
    n
  end

  def size
    @hash.size
  end
  alias length size

  def empty?
    @hash.empty?
  end

  def clear
    @hash.clear
    self
  end

  def replace(enum)
    enum.is_a?(Enumerable) or raise ArgumentError, "value must be enumerable"
    clear
    enum.each { |o| add(o) }
    self
  end

  def to_a
    @hash.keys
  end

  def flatten_merge(set, seen = Set.new)
    set.each { |e|
      if e.is_a?(Set)
	if seen.include?(e_id = e.id)
	  raise ArgumentError, "tried to flatten recursive Set"
	end

	seen.add(e_id)
	flatten_merge(e, seen)
	seen.delete(e_id)
      else
	add(e)
      end
    }

    self
  end
  protected :flatten_merge

  def flatten
    type.new.flatten_merge(self)
  end

  def flatten!
    if detect { |e| e.is_a?(Set) }
      replace(flatten())
    else
      nil
    end
  end

  def include?(o)
    @hash.include?(o)
  end
  alias member? include?

  def contain?(enum)
    enum.is_a?(Enumerable) or raise ArgumentError, "value must be enumerable"
    enum.all? { |o| include?(o) }
  end

  def each
    @hash.each_key { |o| yield o }
  end

  def add(o)
    @hash[o] = true
    self
  end
  alias << add

  def delete(o)
    @hash.delete(o) ? o : nil
  end

  def delete_if
    @hash.delete_if { |key, value| yield(key) }
    self
  end

  def reject!
    n = @hash.size
    @hash.delete_if { |key, value| yield(key) }
    @hash.size == n ? nil : self
  end

  def merge(enum)
    enum.is_a?(Enumerable) or raise ArgumentError, "value must be enumerable"
    enum.each { |o| add(o) }
    self
  end

  def subtract(enum)
    enum.is_a?(Enumerable) or raise ArgumentError, "value must be enumerable"
    enum.each { |o| delete(o) }
    self
  end

  def +(enum)
    enum.is_a?(Enumerable) or raise ArgumentError, "value must be enumerable"
    n = dup
    enum.each { |o| n.add(o) }
    n
  end
  alias | +	##

  def -(enum)
    enum.is_a?(Enumerable) or raise ArgumentError, "value must be enumerable"
    n = dup
    enum.each { |o| n.delete(o) }
    n
  end

  def &(enum)
    enum.is_a?(Enumerable) or raise ArgumentError, "value must be enumerable"
    n = type.new
    enum.each { |o| include?(o) and n.add(o) }
    n
  end

  def ^(enum)
    enum.is_a?(Enumerable) or raise ArgumentError, "value must be enumerable"
    n = dup
    enum.each { |o| if n.include?(o) then n.delete(o) else n.add(o) end }
    n
  end

  def ==(set)
    equal?(set) and return true

    set.is_a?(Set) && size == set.size or return false

    set.all? { |o| include?(o) }
  end

  def hash
    @hash.hash
  end

  def eql?(o)
    @hash.hash == o.hash
  end

  def classify
    h = {}

    each { |i|
      x = yield(i)
      (h[x] ||= type.new).add(i)
    }

    h
  end

  def divide(&func)
    if func.arity == 2
      require 'tsort'

      class << dig = {}
	include TSort

	alias tsort_each_node each_key
	def tsort_each_child(node, &block)
	  fetch(node).each(&block)
	end
      end

      each { |u|
	dig[u] = a = []
	each{ |v| func.call(u, v) and a << v }
      }

      set = type.new()
      dig.each_strongly_connected_component { |css|
	set.add(Set.new(css))
      }
      set
    else
      type.new(classify(&func).values)
    end
  end

  InspectKey = :__inspect_key__

  def inspect
    ids = (Thread.current[InspectKey] ||= [])

    if ids.include?(id)
      return sprintf('#<%s: {...}>', type.name)
    end

    begin
      ids << id
      return sprintf('#<%s: {%s}>', type, to_a.inspect[1..-2])
    ensure
      ids.pop
    end
  end

  def pretty_print(pp)
    pp.text sprintf('#<%s: {', type.name)
    pp.nest(1) {
      first = true
      each { |o|
	if first
	  first = false
	else
	  pp.text ","
	  pp.breakable
	end
	pp.pp o
      }
    }
    pp.text "}>"
  end

  def pretty_print_cycle(pp)
    pp.text sprintf('#<%s: {%s}>', type.name, empty? ? '' : '...')
  end
end

if $0 == __FILE__
  eval DATA.read
end

__END__

require 'test/unit'
require 'test/unit/ui/console/testrunner'

class TC_Set < Test::Unit::TestCase
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
      Set.new('XYZ')
    }
    assert_raises(ArgumentError) {
      Set.new(false)
    }
    assert_raises(ArgumentError) {
      Set.new(1)
    }
    assert_raises(ArgumentError) {
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

    # test3; multiple occurences of a set in an set
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

    assert_raises(ArgumentError) {
      set1.flatten!
    }

    # test5; miscellaneus
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

  def test_contain?
    set = Set[1,2,3]

    assert_raises(ArgumentError) {
      set.contain?()
    }

    assert_raises(ArgumentError) {
      set.contain?(2)
    }

    assert_equal(true, set.contain?([]))
    assert_equal(true, set.contain?([3,1]))
    assert_equal(false, set.contain?([1,2,0]))

    assert_equal(true, Set[].contain?([]))
  end

  def test_each
    ary = [1,3,5,7,10,20]
    set = Set.new(ary)

    assert_raises(LocalJumpError) {
      set.each
    }

    assert_nothing_raised {
      set.each { |o|
	ary.delete(o) or raise "unexpected element: #{o}"
      }

      ary.empty? or raise "forgotten elements: #{ary.join(', ')}"
    }
  end

  def test_add
    set = Set[1,2,3]

    ret = set.add(2)
    assert_same(set, ret)
    assert_equal(Set[1,2,3], set)

    ret = set.add(4)
    assert_same(set, ret)
    assert_equal(Set[1,2,3,4], set)
  end

  def test_delete
    set = Set[1,2,3]

    ret = set.delete(4)
    assert_same(nil, ret)
    assert_equal(Set[1,2,3], set)

    ret = set.delete(2)
    assert_equal(2, ret)
    assert_equal(Set[1,3], set)
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

  def test_reject!
    set = Set.new(1..10)
    ret = set.reject! { |i| i > 10 }
    assert_same(nil, ret)
    assert_equal(Set.new(1..10), set)

    set = Set.new(1..10)
    ret = set.delete_if { |i| i % 3 == 0 }
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

  def test_eq
    set1 = Set[2,3,1]
    set2 = Set[1,2,3]

    assert_equal(set1, set1)
    assert_equal(set1, set2)
    assert_not_equal(Set[1], [1])

    set1 = Class.new(Set)["a", "b"]
    set2 = Set["a", "b", set1]
    set1 = set1.add(set1.clone)

    assert_equal(set1, set2)
    assert_equal(set2, set1)
    assert_equal(set2, set2.clone)
    assert_equal(set1.clone, set1)
  end

  # def test_hash
  # end

  # def test_eql?
  # end

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

  def test_inspect
    set1 = Set[1]

    assert_equal('#<Set: {1}>', set1.inspect)

    set2 = Set[Set[0], 1, 2, set1]
    assert_equal(false, set2.inspect.include?('#<Set: {...}>'))

    set1.add(set2)
    assert_equal(true, set1.inspect.include?('#<Set: {...}>'))
  end

  # def test_pretty_print
  # end

  # def test_pretty_print_cycle
  # end
end

Test::Unit::UI::Console::TestRunner.run(TC_Set)
