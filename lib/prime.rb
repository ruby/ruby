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

  # Returns true if +self+ is a prime number, false for a composite.
  def prime?
    Prime.prime?(self)
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
#  Prime.each(100) do |prime|
#    p prime  #=> 2, 3, 5, 7, 11, ...., 97
#  end
#
# == Retrieving the instance
# +Prime+.new is obsolete. Now +Prime+ has the default instance and you can 
# access it as +Prime+.instance.
#
# For convenience, each instance method of +Prime+.instance can be accessed
# as a class method of +Prime+. 
#
# e.g.
#  Prime.instance.prime?(2)  #=> true
#  Prime.prime?(2)           #=> true
#
# == Generators
# A "generator" provides an implementation of enumerating pseudo-prime
# numbers and it remembers the position of enumeration and upper bound.
# Futhermore, it is a external iterator of prime enumeration which is 
# compatible to an Enumerator.
#
# +Prime+::+PseudoPrimeGenerator+ is the base class for generators.
# There are few implementations of generator.
#
# [+Prime+::+EratosthenesGenerator+]
#   Uses eratosthenes's sieve. 
# [+Prime+::+TrialDivisionGenerator+]
#   Uses the trial division method.
# [+Prime+::+Generator23+]
#   Generates all positive integers which is not divided by 2 nor 3.
#   This sequence is very bad as a pseudo-prime sequence. But this 
#   is faster and uses much less memory than other generators. So,
#   it is suitable for factorizing an integer which is not large but
#   has many prime factors. e.g. for Prime#prime? .
class Prime
  include Enumerable
  @the_instance = Prime.new

  # obsolete. Use +Prime+::+instance+ or class methods of +Prime+.
  def initialize
    @generator = EratosthenesGenerator.new
    extend OldCompatibility
    warn "Prime::new is obsolete. use Prime::instance or class methods of Prime."
  end

  class<<self
    extend Forwardable
    include Enumerable
    # Returns the default instance of Prime.
    def instance; @the_instance end

    def method_added(method) # :nodoc:
      (class<<self;self;end).def_delegator :instance, method
    end
  end

  # Iterates the given block over all prime numbers.
  #
  # == Parameters
  # +ubound+::
  #   Optional. An arbitrary positive number. 
  #   The upper bound of enumeration. The method enumerates
  #   prime numbers infinitely if +ubound+ is nil. 
  # +generator+::
  #   Optional. An implementation of pseudo-prime generator.
  #
  # == Return value
  # An evaluated value of the given block at the last time.
  # Or an enumerator which is compatible to an +Enumerator+
  # if no block given. 
  #
  # == Description
  # Calls +block+ once for each prime numer, passing the prime as
  # a parameter.
  #
  # +ubound+::
  #   Upper bound of prime numbers. The iterator stops after 
  #   yields all prime numbers p <= +ubound+.
  #
  # == Note
  # +Prime+.+new+ returns a object extended by +Prime+::+OldCompatibility+
  # in order to compatibility to Ruby 1.9, and +Prime+#each is overwritten
  # by +Prime+::+OldCompatibility+#+each+.
  #
  # +Prime+.+new+ is now obsolete. Use +Prime+.+instance+.+each+ or simply
  # +Prime+.+each+.
  def each(ubound = nil, generator = EratosthenesGenerator.new, &block)
    generator.upper_bound = ubound
    generator.each(&block)
  end


  # Returns true if +value+ is prime, false for a composite.
  #
  # == Parameters
  # +value+:: an arbitrary integer to be checked.
  # +generator+:: optional. A pseudo-prime generator.
  def prime?(value, generator = Prime::Generator23.new)
    for num in generator
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
  # For [[p_1, e_1], [p_2, e_2], ...., [p_n, e_n]], it returns
  # p_1**e_1 * p_2**e_2 * .... * p_n**e_n.
  #
  #  Prime.int_from_prime_division([[2,2], [3,1]])  #=> 12
  def int_from_prime_division(pd)
    pd.inject(1){|value, (prime, index)|
      value *= prime**index
    }
  end

  # Returns the factorization of +value+.
  #
  # == Parameters
  # +value+:: An arbitrary integer.
  # +generator+:: Optional. A pseudo-prime generator.
  #               +generator+.succ must return the next 
  #               pseudo-prime number in the ascendent
  #               order. It must generate all prime numbers,
  #               but may generate non prime numbers.
  #
  # === Exceptions
  # +ZeroDivisionError+:: when +value+ is zero.
  #
  # == Example
  # For an arbitrary integer 
  # n = p_1**e_1 * p_2**e_2 * .... * p_n**e_n,
  # prime_division(n) returns
  # [[p_1, e_1], [p_2, e_2], ...., [p_n, e_n]].
  #
  #  Prime.prime_division(12) #=> [[2,2], [3,1]]
  #
  def prime_division(value, generator= Prime::Generator23.new)
    raise ZeroDivisionError if value == 0
    pv = []
    for prime in generator
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
    return pv
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

    # Iterates the given block for each prime numbers.
    def each(&block)
      return self.dup unless block
      if @ubound
	last_value = nil
	loop do
	  prime = succ
	  break last_value if prime > @ubound
	  last_value = block.call(prime)
	end
      else
	loop do
	  block.call(succ)
	end
      end
    end

    # see +Enumerator+#with_index.
    alias with_index each_with_index

    # see +Enumerator+#with_object.
    def with_object(obj)
      return enum_for(:with_object) unless block_given?
      each do |prime|
	yield prime, obj
      end
    end
  end
  
  # An implementation of +PseudoPrimeGenerator+.
  #
  # Uses +EratosthenesSieve+.
  class EratosthenesGenerator < PseudoPrimeGenerator
    def initialize
      @last_prime = nil
    end
    
    def succ
      @last_prime = @last_prime ? EratosthenesSieve.instance.next_to(@last_prime) : 2
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
    end
    
    def succ
      TrialDivision.instance[@index += 1]
    end
    def rewind
      initialize
    end
    alias next succ
  end

  # Generates all integer which are greater than 2 and
  # are not divided by 2 nor 3.
  #
  # This is a pseudo-prime generator, suitable on 
  # checking primality of a integer by brute force 
  # method.
  class Generator23<PseudoPrimeGenerator
    def initialize
      @prime = 1
      @step = nil
    end
    
    def succ
      loop do
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
	return @prime
      end
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
      return @primes
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
      return @primes[index]
    end
  end

  # Internal use. An implementation of eratosthenes's sieve
  class EratosthenesSieve
    include Singleton

    def initialize # :nodoc:
      # bitmap for odd prime numbers less than 256.
      # For an arbitrary odd number n, @table[i][j] is 1 when n is prime where i,j = n.divmod(32) .
      @table = [0xcb6e, 0x64b4, 0x129a, 0x816d, 0x4c32, 0x864a, 0x820d, 0x2196]
    end

    # returns the least odd prime number which is greater than +n+.
    def next_to(n)
      n = (n-1).div(2)*2+3 # the next odd number of given n
      i,j = n.divmod(32)
      loop do
	extend_table until @table.length > i
	if !@table[i].zero?
	  (j...32).step(2) do |k|
	    return 32*i+k if !@table[i][k.div(2)].zero?
	  end
	end
	i += 1; j = 1
      end
    end

    private
    def extend_table
      orig_len = @table.length
      new_len = [orig_len**2, orig_len+256].min
      lbound = orig_len*32
      ubound = new_len*32
      @table.fill(0xFFFF, orig_len...new_len)
      (3..Integer(Math.sqrt(ubound))).step(2) do |p|
	i, j = p.divmod(32)
	next if @table[i][j.div(2)].zero?

	start = (lbound.div(2*p)*2+1)*p    # odd multiple of p which is greater than or equal to lbound
	(start...ubound).step(2*p) do |n|
	  i, j = n.divmod(32)
	  @table[i] &= 0xFFFF ^ (1<<(j.div(2)))
	end
      end
    end
  end

  # Provides a +Prime+ object with compatibility to Ruby 1.8 when instanciated via +Prime+.+new+.
  module OldCompatibility
    # Returns the next prime number and forwards internal pointer.
    def succ
      @generator.succ
    end
    alias next succ

    # Overwrites Prime#each.
    #
    # Iterates the given block over all prime numbers. Note that enumeration starts from
    # the current position of internal pointer, not rewound.
    def each(&block)
      return @generator.dup unless block_given?
      loop do
	yield succ
      end
    end
  end
end
