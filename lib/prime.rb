# frozen_string_literal: false
#
# = prime.rb
#
# Prime numbers and factorization library.
#
# Copyright::
#   Copyright (c) 1998-2008 Keiju ISHITSUKA(SHL Japan Inc.)
#   Copyright (c) 2008 Yuki Sonoda (Yugui) <yugui@yugui.jp>
#
# Documentation::
#   Yuki Sonoda
#

require "singleton"
require "forwardable"

class Integer
  # Re-composes a prime factorization and returns the product.
  #
  # See Prime#int_from_prime_division for more details.
  def Integer.from_prime_division(pd)
    Prime.int_from_prime_division(pd)
  end

  # Returns the factorization of +self+.
  #
  # See Prime#prime_division for more details.
  def prime_division(generator = Prime::Generator23.new)
    Prime.prime_division(self, generator)
  end

  # Returns true if +self+ is a prime number, else returns false.
  def prime?
    return self >= 2 if self <= 3
    return false if self % 2 == 0 or self % 3 == 0
    (5..(self**0.5).floor).step(6).each do |i|
      if self % i == 0 || self % (i + 2) == 0
        return false
      end
    end
    true
  end

  # Iterates the given block over all prime numbers.
  #
  # See +Prime+#each for more details.
  def Integer.each_prime(ubound, &block) # :yields: prime
    Prime.each(ubound, &block)
  end
end

#
# The set of all prime numbers.
#
# == Example
#
#   Prime.each(100) do |prime|
#     p prime  #=> 2, 3, 5, 7, 11, ...., 97
#   end
#
# Prime is Enumerable:
#
#   Prime.first 5 # => [2, 3, 5, 7, 11]
#
# == Retrieving the instance
#
# For convenience, each instance method of +Prime+.instance can be accessed
# as a class method of +Prime+.
#
# e.g.
#   Prime.instance.prime?(2)  #=> true
#   Prime.prime?(2)           #=> true
#
# == Generators
#
# A "generator" provides an implementation of enumerating pseudo-prime
# numbers and it remembers the position of enumeration and upper bound.
# Furthermore, it is an external iterator of prime enumeration which is
# compatible with an Enumerator.
#
# +Prime+::+PseudoPrimeGenerator+ is the base class for generators.
# There are few implementations of generator.
#
# [+Prime+::+EratosthenesGenerator+]
#   Uses eratosthenes' sieve.
# [+Prime+::+TrialDivisionGenerator+]
#   Uses the trial division method.
# [+Prime+::+Generator23+]
#   Generates all positive integers which are not divisible by either 2 or 3.
#   This sequence is very bad as a pseudo-prime sequence. But this
#   is faster and uses much less memory than the other generators. So,
#   it is suitable for factorizing an integer which is not large but
#   has many prime factors. e.g. for Prime#prime? .

class Prime
  include Enumerable
  include Singleton

  class << self
    extend Forwardable
    include Enumerable

    def method_added(method) # :nodoc:
      (class<< self;self;end).def_delegator :instance, method
    end
  end

  # Iterates the given block over all prime numbers.
  #
  # == Parameters
  #
  # +ubound+::
  #   Optional. An arbitrary positive number.
  #   The upper bound of enumeration. The method enumerates
  #   prime numbers infinitely if +ubound+ is nil.
  # +generator+::
  #   Optional. An implementation of pseudo-prime generator.
  #
  # == Return value
  #
  # An evaluated value of the given block at the last time.
  # Or an enumerator which is compatible to an +Enumerator+
  # if no block given.
  #
  # == Description
  #
  # Calls +block+ once for each prime number, passing the prime as
  # a parameter.
  #
  # +ubound+::
  #   Upper bound of prime numbers. The iterator stops after it
  #   yields all prime numbers p <= +ubound+.
  #
  def each(ubound = nil, generator = EratosthenesGenerator.new, &block)
    generator.upper_bound = ubound
    generator.each(&block)
  end


  # Returns true if +value+ is a prime number, else returns false.
  #
  # == Parameters
  #
  # +value+:: an arbitrary integer to be checked.
  # +generator+:: optional. A pseudo-prime generator.
  def prime?(value, generator = Prime::Generator23.new)
    raise ArgumentError, "Expected a prime generator, got #{generator}" unless generator.respond_to? :each
    raise ArgumentError, "Expected an integer, got #{value}" unless value.respond_to?(:integer?) && value.integer?
    return false if value < 2
    generator.each do |num|
      q,r = value.divmod num
      return true if q < num
      return false if r == 0
    end
  end

  # Re-composes a prime factorization and returns the product.
  #
  # == Parameters
  # +pd+:: Array of pairs of integers. The each internal
  #        pair consists of a prime number -- a prime factor --
  #        and a natural number -- an exponent.
  #
  # == Example
  # For <tt>[[p_1, e_1], [p_2, e_2], ...., [p_n, e_n]]</tt>, it returns:
  #
  #   p_1**e_1 * p_2**e_2 * .... * p_n**e_n.
  #
  #   Prime.int_from_prime_division([[2,2], [3,1]])  #=> 12
  def int_from_prime_division(pd)
    pd.inject(1){|value, (prime, index)|
      value * prime**index
    }
  end

  # Returns the factorization of +value+.
  #
  # == Parameters
  # +value+:: An arbitrary integer.
  # +generator+:: Optional. A pseudo-prime generator.
  #               +generator+.succ must return the next
  #               pseudo-prime number in the ascending
  #               order. It must generate all prime numbers,
  #               but may also generate non prime numbers too.
  #
  # === Exceptions
  # +ZeroDivisionError+:: when +value+ is zero.
  #
  # == Example
  # For an arbitrary integer:
  #
  #   n = p_1**e_1 * p_2**e_2 * .... * p_n**e_n,
  #
  # prime_division(n) returns:
  #
  #   [[p_1, e_1], [p_2, e_2], ...., [p_n, e_n]].
  #
  #   Prime.prime_division(12) #=> [[2,2], [3,1]]
  #
  def prime_division(value, generator = Prime::Generator23.new)
    raise ZeroDivisionError if value == 0
    if value < 0
      value = -value
      pv = [[-1, 1]]
    else
      pv = []
    end
    generator.each do |prime|
      count = 0
      while (value1, mod = value.divmod(prime)
             mod) == 0
        value = value1
        count += 1
      end
      if count != 0
        pv.push [prime, count]
      end
      break if value1 <= prime
    end
    if value > 1
      pv.push [value, 1]
    end
    pv
  end

  # An abstract class for enumerating pseudo-prime numbers.
  #
  # Concrete subclasses should override succ, next, rewind.
  class PseudoPrimeGenerator
    include Enumerable

    def initialize(ubound = nil)
      @ubound = ubound
    end

    def upper_bound=(ubound)
      @ubound = ubound
    end
    def upper_bound
      @ubound
    end

    # returns the next pseudo-prime number, and move the internal
    # position forward.
    #
    # +PseudoPrimeGenerator+#succ raises +NotImplementedError+.
    def succ
      raise NotImplementedError, "need to define `succ'"
    end

    # alias of +succ+.
    def next
      raise NotImplementedError, "need to define `next'"
    end

    # Rewinds the internal position for enumeration.
    #
    # See +Enumerator+#rewind.
    def rewind
      raise NotImplementedError, "need to define `rewind'"
    end

    # Iterates the given block for each prime number.
    def each
      return self.dup unless block_given?
      if @ubound
        last_value = nil
        loop do
          prime = succ
          break last_value if prime > @ubound
          last_value = yield prime
        end
      else
        loop do
          yield succ
        end
      end
    end

    # see +Enumerator+#with_index.
    def with_index(offset = 0)
      return enum_for(:with_index, offset) { Float::INFINITY } unless block_given?
      return each_with_index(&proc) if offset == 0

      each do |prime|
        yield prime, offset
        offset += 1
      end
    end

    # see +Enumerator+#with_object.
    def with_object(obj)
      return enum_for(:with_object, obj) { Float::INFINITY } unless block_given?
      each do |prime|
        yield prime, obj
      end
    end

    def size
      Float::INFINITY
    end
  end

  # An implementation of +PseudoPrimeGenerator+.
  #
  # Uses +EratosthenesSieve+.
  class EratosthenesGenerator < PseudoPrimeGenerator
    def initialize
      @last_prime_index = -1
      super
    end

    def succ
      @last_prime_index += 1
      EratosthenesSieve.instance.get_nth_prime(@last_prime_index)
    end
    def rewind
      initialize
    end
    alias next succ
  end

  # An implementation of +PseudoPrimeGenerator+ which uses
  # a prime table generated by trial division.
  class TrialDivisionGenerator<PseudoPrimeGenerator
    def initialize
      @index = -1
      super
    end

    def succ
      TrialDivision.instance[@index += 1]
    end
    def rewind
      initialize
    end
    alias next succ
  end

  # Generates all integers which are greater than 2 and
  # are not divisible by either 2 or 3.
  #
  # This is a pseudo-prime generator, suitable on
  # checking primality of an integer by brute force
  # method.
  class Generator23<PseudoPrimeGenerator
    def initialize
      @prime = 1
      @step = nil
      super
    end

    def succ
      if (@step)
        @prime += @step
        @step = 6 - @step
      else
        case @prime
        when 1; @prime = 2
        when 2; @prime = 3
        when 3; @prime = 5; @step = 2
        end
      end
      @prime
    end
    alias next succ
    def rewind
      initialize
    end
  end

  # Internal use. An implementation of prime table by trial division method.
  class TrialDivision
    include Singleton

    def initialize # :nodoc:
      # These are included as class variables to cache them for later uses.  If memory
      #   usage is a problem, they can be put in Prime#initialize as instance variables.

      # There must be no primes between @primes[-1] and @next_to_check.
      @primes = [2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37, 41, 43, 47, 53, 59, 61, 67, 71, 73, 79, 83, 89, 97, 101]
      # @next_to_check % 6 must be 1.
      @next_to_check = 103            # @primes[-1] - @primes[-1] % 6 + 7
      @ulticheck_index = 3            # @primes.index(@primes.reverse.find {|n|
      #   n < Math.sqrt(@@next_to_check) })
      @ulticheck_next_squared = 121   # @primes[@ulticheck_index + 1] ** 2
    end

    # Returns the cached prime numbers.
    def cache
      @primes
    end
    alias primes cache
    alias primes_so_far cache

    # Returns the +index+th prime number.
    #
    # +index+ is a 0-based index.
    def [](index)
      while index >= @primes.length
        # Only check for prime factors up to the square root of the potential primes,
        #   but without the performance hit of an actual square root calculation.
        if @next_to_check + 4 > @ulticheck_next_squared
          @ulticheck_index += 1
          @ulticheck_next_squared = @primes.at(@ulticheck_index + 1) ** 2
        end
        # Only check numbers congruent to one and five, modulo six. All others

        #   are divisible by two or three.  This also allows us to skip checking against
        #   two and three.
        @primes.push @next_to_check if @primes[2..@ulticheck_index].find {|prime| @next_to_check % prime == 0 }.nil?
        @next_to_check += 4
        @primes.push @next_to_check if @primes[2..@ulticheck_index].find {|prime| @next_to_check % prime == 0 }.nil?
        @next_to_check += 2
      end
      @primes[index]
    end
  end

  # Internal use. An implementation of eratosthenes' sieve
  class EratosthenesSieve
    include Singleton

    def initialize
      @primes = [2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37, 41, 43, 47, 53, 59, 61, 67, 71, 73, 79, 83, 89, 97, 101]
      # @max_checked must be an even number
      @max_checked = @primes.last + 1
    end

    def get_nth_prime(n)
      compute_primes while @primes.size <= n
      @primes[n]
    end

    private
    def compute_primes
      # max_segment_size must be an even number
      max_segment_size = 1e6.to_i
      max_cached_prime = @primes.last
      # do not double count primes if #compute_primes is interrupted
      # by Timeout.timeout
      @max_checked = max_cached_prime + 1 if max_cached_prime > @max_checked

      segment_min = @max_checked
      segment_max = [segment_min + max_segment_size, max_cached_prime * 2].min
      root = Integer(Math.sqrt(segment_max).floor)

      segment = ((segment_min + 1) .. segment_max).step(2).to_a

      (1..Float::INFINITY).each do |sieving|
        prime = @primes[sieving]
        break if prime > root
        composite_index = (-(segment_min + 1 + prime) / 2) % prime
        while composite_index < segment.size do
          segment[composite_index] = nil
          composite_index += prime
        end
      end

      @primes.concat(segment.compact!)

      @max_checked = segment_max
    end
  end
end
