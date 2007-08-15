#!/usr/bin/env ruby
#--
# $Idaemons: /home/cvs/rb/generator.rb,v 1.8 2001/10/03 08:54:32 knu Exp $
# $RoughId: generator.rb,v 1.10 2003/10/14 19:36:58 knu Exp $
# $Id: generator.rb,v 1.2.2.2 2004/05/07 08:48:23 matz Exp $
#++
#
# = generator.rb: convert an internal iterator to an external one
#
# Copyright (c) 2001,2003 Akinori MUSHA <knu@iDaemons.org>
#
# All rights reserved.  You can redistribute and/or modify it under
# the same terms as Ruby.
#
# == Overview
#
# This library provides the Generator class, which converts an
# internal iterator (i.e. an Enumerable object) to an external
# iterator.  In that form, you can roll many iterators independently.
#
# The SyncEnumerator class, which is implemented using Generator,
# makes it easy to roll many Enumerable objects synchronously.
#
# See the respective classes for examples of usage.


#
# Generator converts an internal iterator (i.e. an Enumerable object)
# to an external iterator.
#
# Note that it is not very fast since it is implemented using
# continuations, which are currently slow.
#
# == Example
#
#   require 'generator'
#
#   # Generator from an Enumerable object
#   g = Generator.new(['A', 'B', 'C', 'Z'])
#
#   while g.next?
#     puts g.next
#   end
#
#   # Generator from a block
#   g = Generator.new { |g|
#     for i in 'A'..'C'
#       g.yield i
#     end
#
#     g.yield 'Z'
#   }
#
#   # The same result as above
#   while g.next?
#     puts g.next
#   end
#   
class Generator
  include Enumerable

  # Creates a new generator either from an Enumerable object or from a
  # block.
  #
  # In the former, block is ignored even if given.
  #
  # In the latter, the given block is called with the generator
  # itself, and expected to call the +yield+ method for each element.
  def initialize(enum = nil, &block)
    if enum
      @block = proc { |g|
	enum.each { |x| g.yield x }
      }
    else
      @block = block
    end

    @index = 0
    @queue = []
    @cont_next = @cont_yield = @cont_endp = nil

    if @cont_next = callcc { |c| c }
      @block.call(self)

      @cont_endp.call(nil) if @cont_endp
    end

    self
  end

  # Yields an element to the generator.
  def yield(value)
    if @cont_yield = callcc { |c| c }
      @queue << value
      @cont_next.call(nil)
    end

    self
  end

  # Returns true if the generator has reached the end.
  def end?()
    if @cont_endp = callcc { |c| c }
      @cont_yield.nil? && @queue.empty?
    else
      @queue.empty?
    end
  end

  # Returns true if the generator has not reached the end yet.
  def next?()
    !end?
  end

  # Returns the current index (position) counting from zero.
  def index()
    @index
  end

  # Returns the current index (position) counting from zero.
  def pos()
    @index
  end

  # Returns the element at the current position and moves forward.
  def next()
    if end?
      raise EOFError, "no more elements available"
    end

    if @cont_next = callcc { |c| c }
      @cont_yield.call(nil) if @cont_yield
    end

    @index += 1

    @queue.shift
  end

  # Returns the element at the current position.
  def current()
    if @queue.empty?
      raise EOFError, "no more elements available"
    end

    @queue.first
  end

  # Rewinds the generator.
  def rewind()
    initialize(nil, &@block) if @index.nonzero?

    self
  end

  # Rewinds the generator and enumerates the elements.
  def each
    rewind

    until end?
      yield self.next
    end

    self
  end
end

#
# SyncEnumerator creates an Enumerable object from multiple Enumerable
# objects and enumerates them synchronously.
#
# == Example
#
#   require 'generator'
#
#   s = SyncEnumerator.new([1,2,3], ['a', 'b', 'c'])
#
#   # Yields [1, 'a'], [2, 'b'], and [3,'c']
#   s.each { |row| puts row.join(', ') }
#
class SyncEnumerator
  include Enumerable

  # Creates a new SyncEnumerator which enumerates rows of given
  # Enumerable objects.
  def initialize(*enums)
    @gens = enums.map { |e| Generator.new(e) }
  end

  # Returns the number of enumerated Enumerable objects, i.e. the size
  # of each row.
  def size
    @gens.size
  end

  # Returns the number of enumerated Enumerable objects, i.e. the size
  # of each row.
  def length
    @gens.length
  end

  # Returns true if the given nth Enumerable object has reached the
  # end.  If no argument is given, returns true if any of the
  # Enumerable objects has reached the end.
  def end?(i = nil)
    if i.nil?
      @gens.detect { |g| g.end? } ? true : false
    else
      @gens[i].end?
    end
  end

  # Enumerates rows of the Enumerable objects.
  def each
    @gens.each { |g| g.rewind }

    loop do
      count = 0

      ret = @gens.map { |g|
	if g.end?
	  count += 1
	  nil
	else
	  g.next
	end
      }

      if count == @gens.size
	break
      end

      yield ret
    end

    self
  end
end

if $0 == __FILE__
  eval DATA.read, nil, $0, __LINE__+4
end

__END__

require 'test/unit'

class TC_Generator < Test::Unit::TestCase
  def test_block1
    g = Generator.new { |g|
      # no yield's
    }

    assert_equal(0, g.pos)
    assert_raises(EOFError) { g.current }
  end

  def test_block2
    g = Generator.new { |g|
      for i in 'A'..'C'
        g.yield i
      end

      g.yield 'Z'
    }

    assert_equal(0, g.pos)
    assert_equal('A', g.current)

    assert_equal(true, g.next?)
    assert_equal(0, g.pos)
    assert_equal('A', g.current)
    assert_equal(0, g.pos)
    assert_equal('A', g.next)

    assert_equal(1, g.pos)
    assert_equal(true, g.next?)
    assert_equal(1, g.pos)
    assert_equal('B', g.current)
    assert_equal(1, g.pos)
    assert_equal('B', g.next)

    assert_equal(g, g.rewind)

    assert_equal(0, g.pos)
    assert_equal('A', g.current)

    assert_equal(true, g.next?)
    assert_equal(0, g.pos)
    assert_equal('A', g.current)
    assert_equal(0, g.pos)
    assert_equal('A', g.next)

    assert_equal(1, g.pos)
    assert_equal(true, g.next?)
    assert_equal(1, g.pos)
    assert_equal('B', g.current)
    assert_equal(1, g.pos)
    assert_equal('B', g.next)

    assert_equal(2, g.pos)
    assert_equal(true, g.next?)
    assert_equal(2, g.pos)
    assert_equal('C', g.current)
    assert_equal(2, g.pos)
    assert_equal('C', g.next)

    assert_equal(3, g.pos)
    assert_equal(true, g.next?)
    assert_equal(3, g.pos)
    assert_equal('Z', g.current)
    assert_equal(3, g.pos)
    assert_equal('Z', g.next)

    assert_equal(4, g.pos)
    assert_equal(false, g.next?)
    assert_raises(EOFError) { g.next }
  end

  def test_each
    a = [5, 6, 7, 8, 9]

    g = Generator.new(a)

    i = 0

    g.each { |x|
      assert_equal(a[i], x)

      i += 1

      break if i == 3
    }

    assert_equal(3, i)

    i = 0

    g.each { |x|
      assert_equal(a[i], x)

      i += 1
    }

    assert_equal(5, i)
  end
end

class TC_SyncEnumerator < Test::Unit::TestCase
  def test_each
    r = ['a'..'f', 1..10, 10..20]
    ra = r.map { |x| x.to_a }

    a = (0...(ra.map {|x| x.size}.max)).map { |i| ra.map { |x| x[i] } }

    s = SyncEnumerator.new(*r)

    i = 0

    s.each { |x|
      assert_equal(a[i], x)

      i += 1

      break if i == 3
    }

    assert_equal(3, i)

    i = 0

    s.each { |x|
      assert_equal(a[i], x)

      i += 1
    }

    assert_equal(a.size, i)
  end
end
