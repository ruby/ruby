class Array
  # call-seq:
  #   each {|element| ... } -> self
  #   each -> new_enumerator
  #
  # With a block given, iterates over the elements of +self+,
  # passing each element to the block;
  # returns +self+:
  #
  #   a = [:foo, 'bar', 2]
  #   a.each {|element|  puts "#{element.class} #{element}" }
  #
  # Output:
  #
  #   Symbol foo
  #   String bar
  #   Integer 2
  #
  # Allows the array to be modified during iteration:
  #
  #   a = [:foo, 'bar', 2]
  #   a.each {|element| puts element; a.clear if element.to_s.start_with?('b') }
  #
  # Output:
  #
  #   foo
  #   bar
  #
  # With no block given, returns a new Enumerator.
  #
  # Related: see {Methods for Iterating}[rdoc-ref:Array@Methods+for+Iterating].

  def each
    Primitive.attr! :inline_block

    unless defined?(yield)
      return Primitive.cexpr! 'SIZED_ENUMERATOR(self, 0, 0, ary_enum_length)'
    end
    _i = 0
    value = nil
    while Primitive.cexpr!(%q{ ary_fetch_next(self, LOCAL_PTR(_i), LOCAL_PTR(value)) })
      yield value
    end
    self
  end

  # call-seq:
  #    array.shuffle!(random: Random) -> array
  #
  # Shuffles the elements of +self+ in place.
  #    a = [1, 2, 3] #=> [1, 2, 3]
  #    a.shuffle!    #=> [2, 3, 1]
  #    a             #=> [2, 3, 1]
  #
  # The optional +random+ argument will be used as the random number generator:
  #    a.shuffle!(random: Random.new(1))  #=> [1, 3, 2]
  def shuffle!(random: Random)
    Primitive.rb_ary_shuffle_bang(random)
  end

  # call-seq:
  #    array.shuffle(random: Random) -> new_ary
  #
  # Returns a new array with elements of +self+ shuffled.
  #    a = [1, 2, 3] #=> [1, 2, 3]
  #    a.shuffle     #=> [2, 3, 1]
  #    a             #=> [1, 2, 3]
  #
  # The optional +random+ argument will be used as the random number generator:
  #    a.shuffle(random: Random.new(1))  #=> [1, 3, 2]
  def shuffle(random: Random)
    Primitive.rb_ary_shuffle(random)
  end

  # call-seq:
  #    array.sample(random: Random) -> object
  #    array.sample(n, random: Random) -> new_ary
  #
  # Returns random elements from +self+.
  #
  # When no arguments are given, returns a random element from +self+:
  #    a = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
  #    a.sample # => 3
  #    a.sample # => 8
  # If +self+ is empty, returns +nil+.
  #
  # When argument +n+ is given, returns a new +Array+ containing +n+ random
  # elements from +self+:
  #    a.sample(3) # => [8, 9, 2]
  #    a.sample(6) # => [9, 6, 10, 3, 1, 4]
  # Returns no more than <tt>a.size</tt> elements
  # (because no new duplicates are introduced):
  #    a.sample(a.size * 2) # => [6, 4, 1, 8, 5, 9, 10, 2, 3, 7]
  # But +self+ may contain duplicates:
  #    a = [1, 1, 1, 2, 2, 3]
  #    a.sample(a.size * 2) # => [1, 1, 3, 2, 1, 2]
  # The argument +n+ must be a non-negative numeric value.
  # The order of the result array is unrelated to the order of +self+.
  # Returns a new empty +Array+ if +self+ is empty.
  #
  # The optional +random+ argument will be used as the random number generator:
  #    a = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
  #    a.sample(random: Random.new(1))     #=> 6
  #    a.sample(4, random: Random.new(1))  #=> [6, 10, 9, 2]
  def sample(n = (ary = false), random: Random)
    if Primitive.mandatory_only?
      # Primitive.cexpr! %{ rb_ary_sample(self, rb_cRandom, Qfalse, Qfalse) }
      Primitive.ary_sample0
    else
      # Primitive.cexpr! %{ rb_ary_sample(self, random, n, ary) }
      Primitive.ary_sample(random, n, ary)
    end
  end

  # call-seq:
  #   first -> object or nil
  #   first(count) -> new_array
  #
  # Returns elements from +self+, or +nil+; does not modify +self+.
  #
  # With no argument given, returns the first element (if available):
  #
  #   a = [:foo, 'bar', 2]
  #   a.first # => :foo
  #   a # => [:foo, "bar", 2]
  #
  # If +self+ is empty, returns +nil+.
  #
  #   [].first # => nil
  #
  # With non-negative integer argument +count+ given,
  # returns the first +count+ elements (as available) in a new array:
  #
  #   a.first(0)  # => []
  #   a.first(2)  # => [:foo, "bar"]
  #   a.first(50) # => [:foo, "bar", 2]
  #
  # Related: see {Methods for Querying}[rdoc-ref:Array@Methods+for+Querying].
  def first n = unspecified = true
    if Primitive.mandatory_only?
      Primitive.attr! :leaf
      Primitive.cexpr! %q{ ary_first(self) }
    else
      if unspecified
        Primitive.cexpr! %q{ ary_first(self) }
      else
        Primitive.cexpr! %q{  ary_take_first_or_last_n(self, NUM2LONG(n), ARY_TAKE_FIRST) }
      end
    end
  end

  # call-seq:
  #   array.last  -> object or nil
  #   array.last(n) -> new_array
  #
  # Returns elements from +self+; +self+ is not modified.
  #
  # When no argument is given, returns the last element:
  #
  #   a = [:foo, 'bar', 2]
  #   a.last # => 2
  #   a # => [:foo, "bar", 2]
  #
  # If +self+ is empty, returns +nil+.
  #
  # When non-negative Integer argument +n+ is given,
  # returns the last +n+ elements in a new +Array+:
  #
  #   a = [:foo, 'bar', 2]
  #   a.last(2) # => ["bar", 2]
  #
  # If <tt>n >= array.size</tt>, returns all elements:
  #
  #   a = [:foo, 'bar', 2]
  #   a.last(50) # => [:foo, "bar", 2]
  #
  # If <tt>n == 0</tt>, returns an new empty +Array+:
  #
  #   a = [:foo, 'bar', 2]
  #   a.last(0) # []
  #
  # Related: #first.
  def last n = unspecified = true
    if Primitive.mandatory_only?
      Primitive.attr! :leaf
      Primitive.cexpr! %q{ ary_last(self) }
    else
      if unspecified
        Primitive.cexpr! %q{ ary_last(self) }
      else
        Primitive.cexpr! %q{ ary_take_first_or_last_n(self, NUM2LONG(n), ARY_TAKE_LAST) }
      end
    end
  end

  #  call-seq:
  #    fetch_values(*indexes) -> new_array
  #    fetch_values(*indexes) {|index| ... } -> new_array
  #
  #  With no block given, returns a new array containing the elements of +self+
  #  at the offsets given by +indexes+;
  #  each of the +indexes+ must be an
  #  {integer-convertible object}[rdoc-ref:implicit_conversion.rdoc@Integer-Convertible+Objects]:
  #
  #    a = [:foo, :bar, :baz]
  #    a.fetch_values(3, 1)   # => [:baz, :foo]
  #    a.fetch_values(3.1, 1) # => [:baz, :foo]
  #    a.fetch_values         # => []
  #
  #  For a negative index, counts backwards from the end of the array:
  #
  #    a.fetch_values([-2, -1]) # [:bar, :baz]
  #
  #  When no block is given, raises an exception if any index is out of range.
  #
  #  With a block given, for each index:
  #
  #  - If the index in in range, uses an element of +self+ (as above).
  #  - Otherwise calls, the block with the index, and uses the block's return value.
  #
  #  Example:
  #
  #    a = [:foo, :bar, :baz]
  #    a.fetch_values(1, 0, 42, 777) {|index| index.to_s}
  #    # => [:bar, :foo, "42", "777"]
  #
  #  Related: see {Methods for Fetching}[rdoc-ref:Array@Methods+for+Fetching].
  def fetch_values(*indexes, &block)
    indexes.map! { |i| fetch(i, &block) }
    indexes
  end
end
