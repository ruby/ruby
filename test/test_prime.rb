# frozen_string_literal: false
require 'test/unit'
require 'prime'
require 'timeout'

class TestPrime < Test::Unit::TestCase
  # The first 100 prime numbers
  PRIMES = [
    2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37,
    41, 43, 47, 53, 59, 61, 67, 71, 73, 79, 83,
    89, 97, 101, 103, 107, 109, 113, 127, 131,
    137, 139, 149, 151, 157, 163, 167, 173, 179,
    181, 191, 193, 197, 199, 211, 223, 227, 229,
    233, 239, 241, 251, 257, 263, 269, 271, 277,
    281, 283, 293, 307, 311, 313, 317, 331, 337,
    347, 349, 353, 359, 367, 373, 379, 383, 389,
    397, 401, 409, 419, 421, 431, 433, 439, 443,
    449, 457, 461, 463, 467, 479, 487, 491, 499,
    503, 509, 521, 523, 541,
  ]
  def test_each
    primes = []
    Prime.each do |p|
      break if p > 541
      primes << p
    end
    assert_equal PRIMES, primes
  end

  def test_each_by_prime_number_theorem
    3.upto(15) do |i|
      max = 2**i
      primes = []
      Prime.each do |p|
        break if p >= max
        primes << p
      end

      # Prime number theorem
      assert_operator primes.length, :>=, max/Math.log(max)
      delta = 0.05
      li = (2..max).step(delta).inject(0){|sum,x| sum + delta/Math.log(x)}
      assert_operator primes.length, :<=, li
    end
  end

  def test_each_without_block
    enum = Prime.each
    assert_respond_to(enum, :each)
    assert_kind_of(Enumerable, enum)
    assert_respond_to(enum, :with_index)
    assert_respond_to(enum, :next)
    assert_respond_to(enum, :succ)
    assert_respond_to(enum, :rewind)
  end

  def test_instance_without_block
    enum = Prime.instance.each
    assert_respond_to(enum, :each)
    assert_kind_of(Enumerable, enum)
    assert_respond_to(enum, :with_index)
    assert_respond_to(enum, :next)
    assert_respond_to(enum, :succ)
    assert_respond_to(enum, :rewind)
  end

  def test_new
    exception = assert_raise(NoMethodError) { Prime.new }
  end

  def test_enumerator_succ
    enum = Prime.each
    assert_equal PRIMES[0, 50], 50.times.map{ enum.succ }
    assert_equal PRIMES[50, 50], 50.times.map{ enum.succ }
    enum.rewind
    assert_equal PRIMES[0, 100], 100.times.map{ enum.succ }
  end

  def test_enumerator_with_index
    enum = Prime.each
    last = -1
    enum.with_index do |p,i|
      break if i >= 100
      assert_equal last+1, i
      assert_equal PRIMES[i], p
      last = i
    end
  end

  def test_enumerator_with_index_with_offset
    enum = Prime.each
    last = 5-1
    enum.with_index(5).each do |p,i|
      break if i >= 100+5
      assert_equal last+1, i
      assert_equal PRIMES[i-5], p
      last = i
    end
  end

  def test_enumerator_with_object
    object = Object.new
    enum = Prime.each
    enum.with_object(object).each do |p, o|
      assert_equal object, o
      break
    end
  end

  def test_enumerator_size
    enum = Prime.each
    assert_equal Float::INFINITY, enum.size
    assert_equal Float::INFINITY, enum.with_object(nil).size
    assert_equal Float::INFINITY, enum.with_index(42).size
  end

  def test_default_instance_does_not_have_compatibility_methods
    assert_not_respond_to(Prime.instance, :succ)
    assert_not_respond_to(Prime.instance, :next)
  end

  def test_prime_each_basic_argument_checking
    assert_raise(ArgumentError) { Prime.prime?(1,2) }
    assert_raise(ArgumentError) { Prime.prime?(1.2) }
  end

  class TestInteger < Test::Unit::TestCase
    def test_prime_division
      pd = PRIMES.inject(&:*).prime_division
      assert_equal PRIMES.map{|p| [p, 1]}, pd

      pd = (-PRIMES.inject(&:*)).prime_division
      assert_equal [-1, *PRIMES].map{|p| [p, 1]}, pd
    end

    def test_from_prime_division
      assert_equal PRIMES.inject(&:*), Integer.from_prime_division(PRIMES.map{|p| [p,1]})

      assert_equal(-PRIMES.inject(&:*), Integer.from_prime_division([[-1, 1]] + PRIMES.map{|p| [p,1]}))
    end

    def test_prime?
      PRIMES.each do |p|
        assert_predicate(p, :prime?)
      end

      composites = (0..PRIMES.last).to_a - PRIMES
      composites.each do |c|
        assert_not_predicate(c, :prime?)
      end

      # mersenne numbers
      assert_predicate((2**31-1), :prime?)
      assert_not_predicate((2**32-1), :prime?)

      # fermat numbers
      assert_predicate((2**(2**4)+1), :prime?)
      assert_not_predicate((2**(2**5)+1), :prime?) # Euler!

      # large composite
      assert_not_predicate(((2**13-1) * (2**17-1)), :prime?)

      # factorial
      assert_not_predicate((2...100).inject(&:*), :prime?)

      # negative
      assert_not_predicate(-1, :prime?)
      assert_not_predicate(-2, :prime?)
      assert_not_predicate(-3, :prime?)
      assert_not_predicate(-4, :prime?)
    end
  end

  def test_eratosthenes_works_fine_after_timeout
    sieve = Prime::EratosthenesSieve.instance
    sieve.send(:initialize)
    # simulates that Timeout.timeout interrupts Prime::EratosthenesSieve#compute_primes
    class << Integer
      alias_method :org_sqrt, :sqrt
    end
    begin
      def Integer.sqrt(n)
        sleep 10 if /compute_primes/ =~ caller.first
        org_sqrt(n)
      end
      assert_raise(Timeout::Error) do
        Timeout.timeout(0.5) { Prime.each(7*37){} }
      end
    ensure
      class << Integer
        alias_method :sqrt, :org_sqrt
        remove_method :org_sqrt
      end
    end

    assert_not_include Prime.each(7*37).to_a, 7*37, "[ruby-dev:39465]"
  end
end
