class Array
  # call-seq:
  #    array.shuffle!(random: Random) -> array
  #
  # Shuffles the elements of +self+ in place.
  #    a = [1, 2, 3] #=> [1, 2, 3]
  #    a.shuffle! #=> [2, 3, 1]
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
  #    a.shuffle #=> [2, 3, 1]
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
  # When argument +n+ is given (but not keyword argument +random+),
  # returns a new \Array containing +n+ random elements from +self+:
  #    a.sample(3) # => [8, 9, 2]
  #    a.sample(6) # => [9, 6, 10, 3, 1, 4]
  # Returns no more than <tt>a.size</tt> elements
  # (because no new duplicates are introduced):
  #    a.sample(a.size * 2) # => [6, 4, 1, 8, 5, 9, 10, 2, 3, 7]
  # But +self+ may contain duplicates:
  #    a = [1, 1, 1, 2, 2, 3]
  #    a.sample(a.size * 2) # => [1, 1, 3, 2, 1, 2]
  # Returns a new empty \Array if +self+ is empty.
  #
  # The optional +random+ argument will be used as the random number generator:
  #    a = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
  #    a.sample(random: Random.new(1))     #=> 6
  #    a.sample(4, random: Random.new(1))  #=> [6, 10, 9, 2]
  def sample(n = (ary = false), random: Random)
    Primitive.rb_ary_sample(random, n, ary)
  end

  #
  #  call-seq:
  #    array.map {|element| ... } -> new_array
  #    array.map -> new_enumerator
  #
  #  Calls the block, if given, with each element of +self+;
  #  returns a new \Array whose elements are the return values from the block:
  #    a = [:foo, 'bar', 2]
  #    a1 = a.map {|element| element.class }
  #    a1 # => [Symbol, String, Integer]
  #
  #  Returns a new \Enumerator if no block given:
  #    a = [:foo, 'bar', 2]
  #    a1 = a.map
  #    a1 # => #<Enumerator: [:foo, "bar", 2]:map>
  #
  #  Array#collect is an alias for Array#map.
  #
  def map
    unless Primitive.block_given_p
      return Primitive.cexpr! 'SIZED_ENUMERATOR(self, 0, 0, ary_enum_length)'
    end
    result = Primitive.cexpr! 'rb_ary_new2(RARRAY_LEN(self))'
    i = 0
    size = Primitive.cexpr! 'rb_ary_length(self)'
    while i < size
      tmp = yield Primitive.cexpr! 'RARRAY_AREF(self, NUM2LONG(i))'
      Primitive.cexpr! 'rb_ary_push(result, tmp)'
      i = Primitive.cexpr! 'rb_int_succ(i)'
    end
    return result
  end
end
