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
  #   shuffle!(random: Random) -> self
  #
  # Shuffles all elements in +self+ into a random order,
  # as selected by the object given by keyword argument +random+;
  # returns +self+:
  #
  #   a =             [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]
  #   a.shuffle! # => [5, 3, 8, 7, 6, 1, 9, 4, 2, 0]
  #   a.shuffle! # => [9, 4, 0, 6, 2, 8, 1, 5, 3, 7]
  #
  #   Duplicate elements are included:
  #
  #   a =             [0, 1, 0, 1, 0, 1, 0, 1, 0, 1]
  #   a.shuffle! # => [1, 0, 0, 1, 1, 0, 1, 0, 0, 1]
  #   a.shuffle! # => [0, 1, 0, 1, 1, 0, 1, 0, 1, 0]
  #
  # The object given with keyword argument +random+ is used as the random number generator.
  #
  # Related: see {Methods for Assigning}[rdoc-ref:Array@Methods+for+Assigning].
  def shuffle!(random: Random)
    Primitive.rb_ary_shuffle_bang(random)
  end

  # call-seq:
  #   shuffle(random: Random) -> new_array
  #
  # Returns a new array containing all elements from +self+ in a random order,
  # as selected by the object given by keyword argument +random+:
  #
  #   a =            [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]
  #   a.shuffle # => [0, 8, 1, 9, 6, 3, 4, 7, 2, 5]
  #   a.shuffle # => [8, 9, 0, 5, 1, 2, 6, 4, 7, 3]
  #
  # Duplicate elements are included:
  #
  #   a =            [0, 1, 0, 1, 0, 1, 0, 1, 0, 1]
  #   a.shuffle # => [1, 0, 1, 1, 0, 0, 1, 0, 0, 1]
  #   a.shuffle # => [1, 1, 0, 0, 0, 1, 1, 0, 0, 1]
  #
  # The object given with keyword argument +random+ is used as the random number generator.
  #
  # Related: see {Methods for Fetching}[rdoc-ref:Array@Methods+for+Fetching].
  def shuffle(random: Random)
    Primitive.rb_ary_shuffle(random)
  end

  # call-seq:
  #   sample(random: Random) -> object
  #   sample(count, random: Random) -> new_ary
  #
  # Returns random elements from +self+,
  # as selected by the object given by keyword argument +random+.
  #
  # With no argument +count+ given, returns one random element from +self+:
  #
  #    a = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]
  #    a.sample # => 3
  #    a.sample # => 8
  #
  # Returns +nil+ if +self+ is empty:
  #
  #    [].sample # => nil
  #
  #
  # With non-negative numeric argument +count+ given,
  # returns a new array containing +count+ random elements from +self+:
  #
  #    a.sample(3) # => [8, 9, 2]
  #    a.sample(6) # => [9, 6, 0, 3, 1, 4]
  #
  # The order of the result array is unrelated to the order of +self+.
  #
  # Returns a new empty +Array+ if +self+ is empty:
  #
  #   [].sample(4) # => []
  #
  # May return duplicates in +self+:
  #
  #    a = [1, 1, 1, 2, 2, 3]
  #    a.sample(a.size) # => [1, 1, 3, 2, 1, 2]
  #
  # Returns no more than <tt>a.size</tt> elements
  # (because no new duplicates are introduced):
  #
  #    a.sample(50) # => [6, 4, 1, 8, 5, 9, 0, 2, 3, 7]
  #
  # The object given with keyword argument +random+ is used as the random number generator:
  #
  #    a = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
  #    a.sample(random: Random.new(1))     #=> 6
  #    a.sample(4, random: Random.new(1))  #=> [6, 10, 9, 2]
  #
  # Related: see {Methods for Fetching}[rdoc-ref:Array@Methods+for+Fetching].
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
  #  last  -> last_object or nil
  #  last(n) -> new_array
  #
  # Returns elements from +self+, or +nil+; +self+ is not modified.
  #
  # With no argument given, returns the last element, or +nil+ if +self+ is empty:
  #
  #   a = [:foo, 'bar', 2]
  #   a.last # => 2
  #   a # => [:foo, "bar", 2]
  #   [].last # => nil
  #
  #
  # With non-negative integer argument +n+ is given,
  # returns a new array containing the trailing +n+ elements of +self+, as available:
  #
  #   a = [:foo, 'bar', 2]
  #   a.last(2)  # => ["bar", 2]
  #   a.last(50) # => [:foo, "bar", 2]
  #   a.last(0)  # => []
  #   [].last(3) # => []
  #
  # Related: see {Methods for Fetching}[rdoc-ref:Array@Methods+for+Fetching].
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
