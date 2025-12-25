# frozen_string_literal: true

# :markup: markdown
#
# set/subclass_compatible.rb - Provides compatibility for set subclasses
#
# Copyright (c) 2002-2024 Akinori MUSHA <knu@iDaemons.org>
#
# Documentation by Akinori MUSHA and Gavin Sinclair.
#
# All rights reserved.  You can redistribute and/or modify it under the same
# terms as Ruby.


class Set
  # This module is automatically included in subclasses of Set, to
  # make them backwards compatible with the pure-Ruby set implementation
  # used before Ruby 4. Users who want to use Set subclasses without
  # this compatibility layer should subclass from Set::CoreSet.
  #
  # Note that Set subclasses that access `@hash` are not compatible even
  # with this support. Such subclasses must be updated to support Ruby 4.
  module SubclassCompatible
    module ClassMethods
      def [](*ary)
        new(ary)
      end
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
      enum.nil? and return

      if block
        do_with_enum(enum) { |o| add(block[o]) }
      else
        merge(enum)
      end
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

    def replace(enum)
      if enum.instance_of?(self.class)
        super
      else
        do_with_enum(enum)  # make sure enum is enumerable before calling clear
        clear
        merge(enum)
      end
    end

    def to_set(*args, &block)
      klass = if args.empty?
        Set
      else
        warn "passing arguments to Enumerable#to_set is deprecated", uplevel: 1
        args.shift
      end
      return self if instance_of?(Set) && klass == Set && block.nil? && args.empty?
      klass.new(self, *args, &block)
    end

    def flatten_merge(set, seen = {}) # :nodoc:
      set.each { |e|
        if e.is_a?(Set)
          case seen[e_id = e.object_id]
          when true
            raise ArgumentError, "tried to flatten recursive Set"
          when false
            next
          end

          seen[e_id] = true
          flatten_merge(e, seen)
          seen[e_id] = false
        else
          add(e)
        end
      }

      self
    end
    protected :flatten_merge

    def flatten
      self.class.new.flatten_merge(self)
    end

    def flatten!
      replace(flatten()) if any?(Set)
    end

    def superset?(set)
      case
      when set.instance_of?(self.class)
        super
      when set.is_a?(Set)
        size >= set.size && set.all?(self)
      else
        raise ArgumentError, "value must be a set"
      end
    end
    alias >= superset?

    def proper_superset?(set)
      case
      when set.instance_of?(self.class)
        super
      when set.is_a?(Set)
        size > set.size && set.all?(self)
      else
        raise ArgumentError, "value must be a set"
      end
    end
    alias > proper_superset?

    def subset?(set)
      case
      when set.instance_of?(self.class)
        super
      when set.is_a?(Set)
        size <= set.size && all?(set)
      else
        raise ArgumentError, "value must be a set"
      end
    end
    alias <= subset?

    def proper_subset?(set)
      case
      when set.instance_of?(self.class)
        super
      when set.is_a?(Set)
        size < set.size && all?(set)
      else
        raise ArgumentError, "value must be a set"
      end
    end
    alias < proper_subset?

    def <=>(set)
      return unless set.is_a?(Set)

      case size <=> set.size
      when -1 then -1 if proper_subset?(set)
      when +1 then +1 if proper_superset?(set)
      else 0 if self.==(set)
      end
    end

    def intersect?(set)
      case set
      when Set
        if size < set.size
          any?(set)
        else
          set.any?(self)
        end
      when Enumerable
        set.any?(self)
      else
        raise ArgumentError, "value must be enumerable"
      end
    end

    def disjoint?(set)
      !intersect?(set)
    end

    def add?(o)
      add(o) unless include?(o)
    end

    def delete?(o)
      delete(o) if include?(o)
    end

    def delete_if(&block)
      block_given? or return enum_for(__method__) { size }
      select(&block).each { |o| delete(o) }
      self
    end

    def keep_if(&block)
      block_given? or return enum_for(__method__) { size }
      reject(&block).each { |o| delete(o) }
      self
    end

    def collect!
      block_given? or return enum_for(__method__) { size }
      set = self.class.new
      each { |o| set << yield(o) }
      replace(set)
    end
    alias map! collect!

    def reject!(&block)
      block_given? or return enum_for(__method__) { size }
      n = size
      delete_if(&block)
      self if size != n
    end

    def select!(&block)
      block_given? or return enum_for(__method__) { size }
      n = size
      keep_if(&block)
      self if size != n
    end

    alias filter! select!

    def merge(*enums, **nil)
      enums.each do |enum|
        if enum.instance_of?(self.class)
          super(enum)
        else
          do_with_enum(enum) { |o| add(o) }
        end
      end

      self
    end

    def subtract(enum)
      do_with_enum(enum) { |o| delete(o) }
      self
    end

    def |(enum)
      dup.merge(enum)
    end
    alias + |
    alias union |

    def -(enum)
      dup.subtract(enum)
    end
    alias difference -

    def &(enum)
      n = self.class.new
      if enum.is_a?(Set)
        if enum.size > size
          each { |o| n.add(o) if enum.include?(o) }
        else
          enum.each { |o| n.add(o) if include?(o) }
        end
      else
        do_with_enum(enum) { |o| n.add(o) if include?(o) }
      end
      n
    end
    alias intersection &

    def ^(enum)
      n = self.class.new(enum)
      each { |o| n.add(o) unless n.delete?(o) }
      n
    end

    def ==(other)
      if self.equal?(other)
        true
      elsif other.instance_of?(self.class)
        super
      elsif other.is_a?(Set) && self.size == other.size
        other.all? { |o| include?(o) }
      else
        false
      end
    end

    def eql?(o)   # :nodoc:
      return false unless o.is_a?(Set)
      super
    end

    def classify
      block_given? or return enum_for(__method__) { size }

      h = {}

      each { |i|
        (h[yield(i)] ||= self.class.new).add(i)
      }

      h
    end

    def join(separator=nil)
      to_a.join(separator)
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
      pp.group(1, sprintf('#<%s:', self.class.name), '>') {
        pp.breakable
        pp.group(1, '{', '}') {
          pp.seplist(self) { |o|
            pp.pp o
          }
        }
      }
    end

    def pretty_print_cycle(pp)    # :nodoc:
      pp.text sprintf('#<%s: {%s}>', self.class.name, empty? ? '' : '...')
    end
  end
  private_constant :SubclassCompatible
end
