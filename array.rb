#!/usr/bin/ruby
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
    __builtin_rb_ary_shuffle(random);
  end
end
