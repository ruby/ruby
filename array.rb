class Array
  # call-seq:
  #    ary.shuffle!              -> ary
  #    ary.shuffle!(random: rng) -> ary
  #
  # Shuffles elements in +self+ in place.
  #
  #    a = [ 1, 2, 3 ]           #=> [1, 2, 3]
  #    a.shuffle!                #=> [2, 3, 1]
  #    a                         #=> [2, 3, 1]
  #
  # The optional +rng+ argument will be used as the random number generator.
  #
  #    a.shuffle!(random: Random.new(1))  #=> [1, 3, 2]
  def shuffle!(random: Random)
    __builtin_rb_ary_shuffle_bang(random)
  end

  # call-seq:
  #    ary.shuffle              -> new_ary
  #    ary.shuffle(random: rng) -> new_ary
  #
  # Returns a new array with elements of +self+ shuffled.
  #
  #    a = [ 1, 2, 3 ]           #=> [1, 2, 3]
  #    a.shuffle                 #=> [2, 3, 1]
  #    a                         #=> [1, 2, 3]
  #
  # The optional +rng+ argument will be used as the random number generator.
  #
  #    a.shuffle(random: Random.new(1))  #=> [1, 3, 2]
  def shuffle(random: Random)
    __builtin_rb_ary_shuffle(random)
  end

  # call-seq:
  #    ary.sample                  -> obj
  #    ary.sample(random: rng)     -> obj
  #    ary.sample(n)               -> new_ary
  #    ary.sample(n, random: rng)  -> new_ary
  #
  # Choose a random element or +n+ random elements from the array.
  #
  # The elements are chosen by using random and unique indices into the array
  # in order to ensure that an element doesn't repeat itself unless the array
  # already contained duplicate elements.
  #
  # If the array is empty the first form returns +nil+ and the second form
  # returns an empty array.
  #
  #    a = [ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 ]
  #    a.sample         #=> 7
  #    a.sample(4)      #=> [6, 4, 2, 5]
  #
  # The optional +rng+ argument will be used as the random number generator.
  #
  #    a.sample(random: Random.new(1))     #=> 6
  #    a.sample(4, random: Random.new(1))  #=> [6, 10, 9, 2]
  def sample(n = (ary = false), random: Random)
    __builtin_rb_ary_sample(random, n, ary)
  end
end
