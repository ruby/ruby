#!/usr/bin/env ruby
#
# Copyright (c) 2001,2003 Akinori MUSHA <knu@iDaemons.org>
#
# All rights reserved.  You can redistribute and/or modify it under
# the same terms as Ruby.
#
# $Idaemons: /home/cvs/rb/generator.rb,v 1.8 2001/10/03 08:54:32 knu Exp $
# $RoughId: generator.rb,v 1.10 2003/10/14 19:36:58 knu Exp $
# $Id$

#
# class Generator - converts an internal iterator to an external iterator
#

class Generator
  include Enumerable

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

  def yield(value)
    if @cont_yield = callcc { |c| c }
      @queue << value
      @cont_next.call(nil)
    end

    self
  end

  def end?()
    if @cont_endp = callcc { |c| c }
      @cont_yield.nil? && @queue.empty?
    else
      @queue.empty?
    end
  end

  def next?()
    !end?
  end

  def index()
    @index
  end

  def pos()
    @index
  end

  def next()
    if end?
      raise EOFError, "no more element is supplied"
    end

    if @cont_next = callcc { |c| c }
      @cont_yield.call(nil) if @cont_yield
    end

    @index += 1

    @queue.shift
  end

  def current()
    if @queue.empty?
      raise EOFError, "no more element is supplied"
    end

    @queue.first
  end

  def rewind()
    initialize(nil, &@block) if @index.nonzero?

    self
  end

  def each
    rewind

    until end?
      yield self.next
    end

    self
  end
end

#
# class SyncEnumerator - enumerates multiple internal iterators synchronously
#

class SyncEnumerator
  include Enumerable

  def initialize(*enums)
    @gens = enums.map { |e| Generator.new(e) }
  end

  def size
    @gens.size
  end

  def length
    @gens.length
  end

  def end?(i = nil)
    if i.nil?
      @gens.detect { |g| g.end? } ? true : false
    else
      @gens[i].end?
    end
  end

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
