#--
# frozen_string_literal: true
#
# set.rb - defines the Set class
#++
# Copyright (c) 2002-2016 Akinori MUSHA <knu@iDaemons.org>
#
# Documentation by Akinori MUSHA and Gavin Sinclair.
#
# All rights reserved.  You can redistribute and/or modify it under the same
# terms as Ruby.
#
#   $Id$
#
# == Overview
#
# This library provides the Set class, which deals with a collection
# of unordered values with no duplicates.  It is a hybrid of Array's
# intuitive inter-operation facilities and Hash's fast lookup.  If you
# need to keep values sorted in some order, use the SortedSet class.
#
# The method +to_set+ is added to Enumerable for convenience.
#
# See the Set and SortedSet documentation for examples of usage.


#
# Set implements a collection of unordered values with no duplicates.
# This is a hybrid of Array's intuitive inter-operation facilities and
# Hash's fast lookup.
#
# Set is easy to use with Enumerable objects (implementing +each+).
# Most of the initializer methods and binary operators accept generic
# Enumerable objects besides sets and arrays.  An Enumerable object
# can be converted to Set using the +to_set+ method.
#
# Set uses Hash as storage, so you must note the following points:
#
# * Equality of elements is determined according to Object#eql? and
#   Object#hash.  Use Set#compare_by_identity to make a set compare
#   its elements by their identity.
# * Set assumes that the identity of each element does not change
#   while it is stored.  Modifying an element of a set will render the
#   set to an unreliable state.
# * When a string is to be stored, a frozen copy of the string is
#   stored instead unless the original string is already frozen.
#
# == Comparison
#
# The comparison operators <, >, <=, and >= are implemented as
# shorthand for the {proper_,}{subset?,superset?} methods.  However,
# the <=> operator is intentionally left out because not every pair of
# sets is comparable ({x, y} vs. {x, z} for example).
#
# == Example
#
#   require 'set'
#   s1 = Set[1, 2]                        #=> #<Set: {1, 2}>
#   s2 = [1, 2].to_set                    #=> #<Set: {1, 2}>
#   s1 == s2                              #=> true
#   s1.add("foo")                         #=> #<Set: {1, 2, "foo"}>
#   s1.merge([2, 6])                      #=> #<Set: {1, 2, "foo", 6}>
#   s1.subset?(s2)                        #=> false
#   s2.subset?(s1)                        #=> true
#
# == Contact
#
#   - Akinori MUSHA <knu@iDaemons.org> (current maintainer)
#
class Set
  include Enumerable

  # Creates a new set containing the given objects.
  #
  #     Set[1, 2]                   # => #<Set: {1, 2}>
  #     Set[1, 2, 1]                # => #<Set: {1, 2}>
  #     Set[1, 'c', :s]             # => #<Set: {1, "c", :s}>
  def self.[](*ary)
    new(ary)
  end

  # Creates a new set containing the elements of the given enumerable
  # object.
  #
  # If a block is given, the elements of enum are preprocessed by the
  # given block.
  #
  #     Set.new([1, 2])                       #=> #<Set: {1, 2}>
  #     Set.new([1, 2, 1])                    #=> #<Set: {1, 2}>
  #     Set.new([1, 'c', :s])                 #=> #<Set: {1, "c", :s}>
  #     Set.new(1..5)                         #=> #<Set: {1, 2, 3, 4, 5}>
  #     Set.new([1, 2, 3]) { |x| x * x }      #=> #<Set: {1, 4, 9}>
  def initialize(enum = nil, &block) # :yields: o
    @hash ||= Hash.new(false)

    enum.nil? and return

    if block
      do_with_enum(enum) { |o| add(block[o]) }
    else
      merge(enum)
    end
  end

  # Makes the set compare its elements by their identity and returns
  # self.  This method may not be supported by all subclasses of Set.
  def compare_by_identity
    if @hash.respond_to?(:compare_by_identity)
      @hash.compare_by_identity
      self
    else
      raise NotImplementedError, "#{self.class.name}\##{__method__} is not implemented"
    end
  end

  # Returns true if the set will compare its elements by their
  # identity.  Also see Set#compare_by_identity.
  def compare_by_identity?
    @hash.respond_to?(:compare_by_identity?) && @hash.compare_by_identity?
  end

  def do_with_enum(enum, &block) # :nodoc:
    if enum.respond_to?(:each_entry)
      enum.each_entry(&block) if block
    elsif enum.respond_to?(:each)
      enum.each(&block) if block
    else
      raise ArgumentError, "value must be enumerable"
    end
  end
  private :do_with_enum

  # Dup internal hash.
  def initialize_dup(orig)
    super
    @hash = orig.instance_variable_get(:@hash).dup
  end

  # Clone internal hash.
  def initialize_clone(orig)
    super
    @hash = orig.instance_variable_get(:@hash).clone
  end

  def freeze    # :nodoc:
    @hash.freeze
    super
  end

  def taint     # :nodoc:
    @hash.taint
    super
  end

  def untaint   # :nodoc:
    @hash.untaint
    super
  end

  # Returns the number of elements.
  def size
    @hash.size
  end
  alias length size

  # Returns true if the set contains no elements.
  def empty?
    @hash.empty?
  end

  # Removes all elements and returns self.
  #
  #     set = Set[1, 'c', :s]             #=> #<Set: {1, "c", :s}>
  #     set.clear                         #=> #<Set: {}>
  #     set                               #=> #<Set: {}>
  def clear
    @hash.clear
    self
  end

  # Replaces the contents of the set with the contents of the given
  # enumerable object and returns self.
  #
  #     set = Set[1, 'c', :s]             #=> #<Set: {1, "c", :s}>
  #     set.replace([1, 2])               #=> #<Set: {1, 2}>
  #     set                               #=> #<Set: {1, 2}>
  def replace(enum)
    if enum.instance_of?(self.class)
      @hash.replace(enum.instance_variable_get(:@hash))
      self
    else
      do_with_enum(enum)  # make sure enum is enumerable before calling clear
      clear
      merge(enum)
    end
  end

  # Converts the set to an array.  The order of elements is uncertain.
  #
  #     Set[1, 2].to_a                    #=> [1, 2]
  #     Set[1, 'c', :s].to_a              #=> [1, "c", :s]
  def to_a
    @hash.keys
  end

  # Returns self if no arguments are given.  Otherwise, converts the
  # set to another with klass.new(self, *args, &block).
  #
  # In subclasses, returns klass.new(self, *args, &block) unless
  # overridden.
  def to_set(klass = Set, *args, &block)
    return self if instance_of?(Set) && klass == Set && block.nil? && args.empty?
    klass.new(self, *args, &block)
  end

  def flatten_merge(set, seen = Set.new) # :nodoc:
    set.each { |e|
      if e.is_a?(Set)
        if seen.include?(e_id = e.object_id)
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

  # Returns a new set that is a copy of the set, flattening each
  # containing set recursively.
  def flatten
    self.class.new.flatten_merge(self)
  end

  # Equivalent to Set#flatten, but replaces the receiver with the
  # result in place.  Returns nil if no modifications were made.
  def flatten!
    replace(flatten()) if any? { |e| e.is_a?(Set) }
  end

  # Returns true if the set contains the given object.
  #
  # Note that <code>include?</code> and <code>member?</code> do not test member
  # equality using <code>==</code> as do other Enumerables.
  #
  # See also Enumerable#include?
  def include?(o)
    @hash[o]
  end
  alias member? include?

  # Returns true if the set is a superset of the given set.
  def superset?(set)
    case
    when set.instance_of?(self.class) && @hash.respond_to?(:>=)
      @hash >= set.instance_variable_get(:@hash)
    when set.is_a?(Set)
      size >= set.size && set.all? { |o| include?(o) }
    else
      raise ArgumentError, "value must be a set"
    end
  end
  alias >= superset?

  # Returns true if the set is a proper superset of the given set.
  def proper_superset?(set)
    case
    when set.instance_of?(self.class) && @hash.respond_to?(:>)
      @hash > set.instance_variable_get(:@hash)
    when set.is_a?(Set)
      size > set.size && set.all? { |o| include?(o) }
    else
      raise ArgumentError, "value must be a set"
    end
  end
  alias > proper_superset?

  # Returns true if the set is a subset of the given set.
  def subset?(set)
    case
    when set.instance_of?(self.class) && @hash.respond_to?(:<=)
      @hash <= set.instance_variable_get(:@hash)
    when set.is_a?(Set)
      size <= set.size && all? { |o| set.include?(o) }
    else
      raise ArgumentError, "value must be a set"
    end
  end
  alias <= subset?

  # Returns true if the set is a proper subset of the given set.
  def proper_subset?(set)
    case
    when set.instance_of?(self.class) && @hash.respond_to?(:<)
      @hash < set.instance_variable_get(:@hash)
    when set.is_a?(Set)
      size < set.size && all? { |o| set.include?(o) }
    else
      raise ArgumentError, "value must be a set"
    end
  end
  alias < proper_subset?

  # Returns true if the set and the given set have at least one
  # element in common.
  #
  #   Set[1, 2, 3].intersect? Set[4, 5]   #=> false
  #   Set[1, 2, 3].intersect? Set[3, 4]   #=> true
  def intersect?(set)
    set.is_a?(Set) or raise ArgumentError, "value must be a set"
    if size < set.size
      any? { |o| set.include?(o) }
    else
      set.any? { |o| include?(o) }
    end
  end

  # Returns true if the set and the given set have no element in
  # common.  This method is the opposite of +intersect?+.
  #
  #   Set[1, 2, 3].disjoint? Set[3, 4]   #=> false
  #   Set[1, 2, 3].disjoint? Set[4, 5]   #=> true
  def disjoint?(set)
    !intersect?(set)
  end

  # Calls the given block once for each element in the set, passing
  # the element as parameter.  Returns an enumerator if no block is
  # given.
  def each(&block)
    block or return enum_for(__method__) { size }
    @hash.each_key(&block)
    self
  end

  # Adds the given object to the set and returns self.  Use +merge+ to
  # add many elements at once.
  #
  #     Set[1, 2].add(3)                    #=> #<Set: {1, 2, 3}>
  #     Set[1, 2].add([3, 4])               #=> #<Set: {1, 2, [3, 4]}>
  #     Set[1, 2].add(2)                    #=> #<Set: {1, 2}>
  def add(o)
    @hash[o] = true
    self
  end
  alias << add

  # Adds the given object to the set and returns self.  If the
  # object is already in the set, returns nil.
  #
  #     Set[1, 2].add?(3)                    #=> #<Set: {1, 2, 3}>
  #     Set[1, 2].add?([3, 4])               #=> #<Set: {1, 2, [3, 4]}>
  #     Set[1, 2].add?(2)                    #=> nil
  def add?(o)
    add(o) unless include?(o)
  end

  # Deletes the given object from the set and returns self.  Use +subtract+ to
  # delete many items at once.
  def delete(o)
    @hash.delete(o)
    self
  end

  # Deletes the given object from the set and returns self.  If the
  # object is not in the set, returns nil.
  def delete?(o)
    delete(o) if include?(o)
  end

  # Deletes every element of the set for which block evaluates to
  # true, and returns self. Returns an enumerator if no block is
  # given.
  def delete_if
    block_given? or return enum_for(__method__) { size }
    # @hash.delete_if should be faster, but using it breaks the order
    # of enumeration in subclasses.
    select { |o| yield o }.each { |o| @hash.delete(o) }
    self
  end

  # Deletes every element of the set for which block evaluates to
  # false, and returns self. Returns an enumerator if no block is
  # given.
  def keep_if
    block_given? or return enum_for(__method__) { size }
    # @hash.keep_if should be faster, but using it breaks the order of
    # enumeration in subclasses.
    reject { |o| yield o }.each { |o| @hash.delete(o) }
    self
  end

  # Replaces the elements with ones returned by collect().
  # Returns an enumerator if no block is given.
  def collect!
    block_given? or return enum_for(__method__) { size }
    set = self.class.new
    each { |o| set << yield(o) }
    replace(set)
  end
  alias map! collect!

  # Equivalent to Set#delete_if, but returns nil if no changes were
  # made. Returns an enumerator if no block is given.
  def reject!(&block)
    block or return enum_for(__method__) { size }
    n = size
    delete_if(&block)
    self if size != n
  end

  # Equivalent to Set#keep_if, but returns nil if no changes were
  # made. Returns an enumerator if no block is given.
  def select!(&block)
    block or return enum_for(__method__) { size }
    n = size
    keep_if(&block)
    self if size != n
  end

  # Merges the elements of the given enumerable object to the set and
  # returns self.
  def merge(enum)
    if enum.instance_of?(self.class)
      @hash.update(enum.instance_variable_get(:@hash))
    else
      do_with_enum(enum) { |o| add(o) }
    end

    self
  end

  # Deletes every element that appears in the given enumerable object
  # and returns self.
  def subtract(enum)
    do_with_enum(enum) { |o| delete(o) }
    self
  end

  # Returns a new set built by merging the set and the elements of the
  # given enumerable object.
  #
  #     Set[1, 2, 3] | Set[2, 4, 5]         #=> #<Set: {1, 2, 3, 4, 5}>
  #     Set[1, 5, 'z'] | (1..6)             #=> #<Set: {1, 5, "z", 2, 3, 4, 6}>
  def |(enum)
    dup.merge(enum)
  end
  alias + |
  alias union |

  # Returns a new set built by duplicating the set, removing every
  # element that appears in the given enumerable object.
  #
  #     Set[1, 3, 5] - Set[1, 5]                #=> #<Set: {3}>
  #     Set['a', 'b', 'z'] - ['a', 'c']         #=> #<Set: {"b", "z"}>
  def -(enum)
    dup.subtract(enum)
  end
  alias difference -

  # Returns a new set containing elements common to the set and the
  # given enumerable object.
  #
  #     Set[1, 3, 5] & Set[3, 2, 1]             #=> #<Set: {3, 1}>
  #     Set['a', 'b', 'z'] & ['a', 'b', 'c']    #=> #<Set: {"a", "b"}>
  def &(enum)
    n = self.class.new
    do_with_enum(enum) { |o| n.add(o) if include?(o) }
    n
  end
  alias intersection &

  # Returns a new set containing elements exclusive between the set
  # and the given enumerable object.  (set ^ enum) is equivalent to
  # ((set | enum) - (set & enum)).
  #
  #     Set[1, 2] ^ Set[2, 3]                   #=> #<Set: {3, 1}>
  #     Set[1, 'b', 'c'] ^ ['b', 'd']           #=> #<Set: {"d", 1, "c"}>
  def ^(enum)
    n = Set.new(enum)
    each { |o| n.add(o) unless n.delete?(o) }
    n
  end

  # Returns true if two sets are equal.  The equality of each couple
  # of elements is defined according to Object#eql?.
  #
  #     Set[1, 2] == Set[2, 1]                       #=> true
  #     Set[1, 3, 5] == Set[1, 5]                    #=> false
  #     Set['a', 'b', 'c'] == Set['a', 'c', 'b']     #=> true
  #     Set['a', 'b', 'c'] == ['a', 'c', 'b']        #=> false
  def ==(other)
    if self.equal?(other)
      true
    elsif other.instance_of?(self.class)
      @hash == other.instance_variable_get(:@hash)
    elsif other.is_a?(Set) && self.size == other.size
      other.all? { |o| @hash.include?(o) }
    else
      false
    end
  end

  def hash      # :nodoc:
    @hash.hash
  end

  def eql?(o)   # :nodoc:
    return false unless o.is_a?(Set)
    @hash.eql?(o.instance_variable_get(:@hash))
  end

  # Resets the internal state after modification to existing elements
  # and returns self.
  #
  # Elements will be reindexed and deduplicated.
  def reset
    if @hash.respond_to?(:rehash)
      @hash.rehash # This should perform frozenness check.
    else
      raise "can't modify frozen #{self.class.name}" if frozen?
    end
    self
  end

  # Returns true if the given object is a member of the set,
  # and false otherwise.
  #
  # Used in case statements:
  #
  #   require 'set'
  #
  #   case :apple
  #   when Set[:potato, :carrot]
  #     "vegetable"
  #   when Set[:apple, :banana]
  #     "fruit"
  #   end
  #   # => "fruit"
  #
  # Or by itself:
  #
  #   Set[1, 2, 3] === 2   #=> true
  #   Set[1, 2, 3] === 4   #=> false
  #
  alias === include?

  # Classifies the set by the return value of the given block and
  # returns a hash of {value => set of elements} pairs.  The block is
  # called once for each element of the set, passing the element as
  # parameter.
  #
  #   require 'set'
  #   files = Set.new(Dir.glob("*.rb"))
  #   hash = files.classify { |f| File.mtime(f).year }
  #   hash       #=> {2000=>#<Set: {"a.rb", "b.rb"}>,
  #              #    2001=>#<Set: {"c.rb", "d.rb", "e.rb"}>,
  #              #    2002=>#<Set: {"f.rb"}>}
  #
  # Returns an enumerator if no block is given.
  def classify # :yields: o
    block_given? or return enum_for(__method__) { size }

    h = {}

    each { |i|
      (h[yield(i)] ||= self.class.new).add(i)
    }

    h
  end

  # Divides the set into a set of subsets according to the commonality
  # defined by the given block.
  #
  # If the arity of the block is 2, elements o1 and o2 are in common
  # if block.call(o1, o2) is true.  Otherwise, elements o1 and o2 are
  # in common if block.call(o1) == block.call(o2).
  #
  #   require 'set'
  #   numbers = Set[1, 3, 4, 6, 9, 10, 11]
  #   set = numbers.divide { |i,j| (i - j).abs == 1 }
  #   set        #=> #<Set: {#<Set: {1}>,
  #              #           #<Set: {11, 9, 10}>,
  #              #           #<Set: {3, 4}>,
  #              #           #<Set: {6}>}>
  #
  # Returns an enumerator if no block is given.
  def divide(&func)
    func or return enum_for(__method__) { size }

    if func.arity == 2
      require 'tsort'

      class << dig = {}         # :nodoc:
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

      set = Set.new()
      dig.each_strongly_connected_component { |css|
        set.add(self.class.new(css))
      }
      set
    else
      Set.new(classify(&func).values)
    end
  end

  InspectKey = :__inspect_key__         # :nodoc:

  # Returns a string containing a human-readable representation of the
  # set ("#<Set: {element1, element2, ...}>").
  def inspect
    ids = (Thread.current[InspectKey] ||= [])

    if ids.include?(object_id)
      return sprintf('#<%s: {...}>', self.class.name)
    end

    ids << object_id
    begin
      return sprintf('#<%s: {%s}>', self.class, to_a.inspect[1..-2])
    ensure
      ids.pop
    end
  end

  alias to_s inspect

  def pretty_print(pp)  # :nodoc:
    pp.text sprintf('#<%s: {', self.class.name)
    pp.nest(1) {
      pp.seplist(self) { |o|
        pp.pp o
      }
    }
    pp.text "}>"
  end

  def pretty_print_cycle(pp)    # :nodoc:
    pp.text sprintf('#<%s: {%s}>', self.class.name, empty? ? '' : '...')
  end
end

#
# SortedSet implements a Set that guarantees that its elements are
# yielded in sorted order (according to the return values of their
# #<=> methods) when iterating over them.
#
# All elements that are added to a SortedSet must respond to the <=>
# method for comparison.
#
# Also, all elements must be <em>mutually comparable</em>: <tt>el1 <=>
# el2</tt> must not return <tt>nil</tt> for any elements <tt>el1</tt>
# and <tt>el2</tt>, else an ArgumentError will be raised when
# iterating over the SortedSet.
#
# == Example
#
#   require "set"
#
#   set = SortedSet.new([2, 1, 5, 6, 4, 5, 3, 3, 3])
#   ary = []
#
#   set.each do |obj|
#     ary << obj
#   end
#
#   p ary # => [1, 2, 3, 4, 5, 6]
#
#   set2 = SortedSet.new([1, 2, "3"])
#   set2.each { |obj| } # => raises ArgumentError: comparison of Fixnum with String failed
#
class SortedSet < Set
  @@setup = false
  @@mutex = Mutex.new

  class << self
    def [](*ary)        # :nodoc:
      new(ary)
    end

    def setup   # :nodoc:
      @@setup and return

      @@mutex.synchronize do
        # a hack to shut up warning
        alias_method :old_init, :initialize

        begin
          require 'rbtree'

          module_eval <<-END, __FILE__, __LINE__+1
            def initialize(*args)
              @hash = RBTree.new
              super
            end

            def add(o)
              o.respond_to?(:<=>) or raise ArgumentError, "value must respond to <=>"
              super
            end
            alias << add
          END
        rescue LoadError
          module_eval <<-END, __FILE__, __LINE__+1
            def initialize(*args)
              @keys = nil
              super
            end

            def clear
              @keys = nil
              super
            end

            def replace(enum)
              @keys = nil
              super
            end

            def add(o)
              o.respond_to?(:<=>) or raise ArgumentError, "value must respond to <=>"
              @keys = nil
              super
            end
            alias << add

            def delete(o)
              @keys = nil
              @hash.delete(o)
              self
            end

            def delete_if
              block_given? or return enum_for(__method__) { size }
              n = @hash.size
              super
              @keys = nil if @hash.size != n
              self
            end

            def keep_if
              block_given? or return enum_for(__method__) { size }
              n = @hash.size
              super
              @keys = nil if @hash.size != n
              self
            end

            def merge(enum)
              @keys = nil
              super
            end

            def each(&block)
              block or return enum_for(__method__) { size }
              to_a.each(&block)
              self
            end

            def to_a
              (@keys = @hash.keys).sort! unless @keys
              @keys
            end

            def freeze
              to_a
              super
            end

            def rehash
              @keys = nil
              super
            end
          END
        end
        # a hack to shut up warning
        remove_method :old_init

        @@setup = true
      end
    end
  end

  def initialize(*args, &block) # :nodoc:
    SortedSet.setup
    initialize(*args, &block)
  end
end

module Enumerable
  # Makes a set from the enumerable object with given arguments.
  # Needs to +require "set"+ to use this method.
  def to_set(klass = Set, *args, &block)
    klass.new(self, *args, &block)
  end
end

# =begin
# == RestricedSet class
# RestricedSet implements a set with restrictions defined by a given
# block.
#
# === Super class
#     Set
#
# === Class Methods
# --- RestricedSet::new(enum = nil) { |o| ... }
# --- RestricedSet::new(enum = nil) { |rset, o| ... }
#     Creates a new restricted set containing the elements of the given
#     enumerable object.  Restrictions are defined by the given block.
#
#     If the block's arity is 2, it is called with the RestrictedSet
#     itself and an object to see if the object is allowed to be put in
#     the set.
#
#     Otherwise, the block is called with an object to see if the object
#     is allowed to be put in the set.
#
# === Instance Methods
# --- restriction_proc
#     Returns the restriction procedure of the set.
#
# =end
#
# class RestricedSet < Set
#   def initialize(*args, &block)
#     @proc = block or raise ArgumentError, "missing a block"
#
#     if @proc.arity == 2
#       instance_eval %{
#       def add(o)
#         @hash[o] = true if @proc.call(self, o)
#         self
#       end
#       alias << add
#
#       def add?(o)
#         if include?(o) || !@proc.call(self, o)
#           nil
#         else
#           @hash[o] = true
#           self
#         end
#       end
#
#       def replace(enum)
#         enum.respond_to?(:each) or raise ArgumentError, "value must be enumerable"
#         clear
#         enum.each_entry { |o| add(o) }
#
#         self
#       end
#
#       def merge(enum)
#         enum.respond_to?(:each) or raise ArgumentError, "value must be enumerable"
#         enum.each_entry { |o| add(o) }
#
#         self
#       end
#       }
#     else
#       instance_eval %{
#       def add(o)
#         if @proc.call(o)
#           @hash[o] = true
#         end
#         self
#       end
#       alias << add
#
#       def add?(o)
#         if include?(o) || !@proc.call(o)
#           nil
#         else
#           @hash[o] = true
#           self
#         end
#       end
#       }
#     end
#
#     super(*args)
#   end
#
#   def restriction_proc
#     @proc
#   end
# end

# Tests have been moved to test/test_set.rb.
