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
    begin
      # simulates that Timeout.timeout interrupts Prime::EratosthenesSieve#extend_table
      def sieve.Integer(n)
        n = super(n)
        sleep 10 if /compute_primes/ =~ caller.first
        return n
      end

      assert_raise(Timeout::Error) do
        Timeout.timeout(0.5) { Prime.each(7*37){} }
      end
    ensure
      class << sieve
        remove_method :Integer
      end
    end

    assert_not_include Prime.each(7*37).to_a, 7*37, "[ruby-dev:39465]"
  end

  def test_probably_prime
    assert_equal Prime.probably_prime?(-1), false
    assert_equal Prime.probably_prime?(0), false
    assert_equal Prime.probably_prime?(1), false
    assert_equal Prime.probably_prime?(2), true
    assert_equal Prime.probably_prime?(961_748_941), true
    assert_equal Prime.probably_prime?(4547337172376300111955330758342147474062293202868155909489), true
    PRIMES[1, PRIMES.length - 1].each do |prime|
      assert_equal Prime.probably_prime?(prime), true
    end

    assert_equal Prime.probably_prime?(314159 * (10 ** 765) + 951413), true
    assert_equal Prime.probably_prime?(1749343240116807117649823543576480140353607282475249), true
    assert_equal Prime.probably_prime?(999999999999999999999999999999999841), true
    assert_equal Prime.probably_prime?(25262728293031323334353637383940414243444546474849), true
    assert_equal Prime.probably_prime?(33452526613163807108170062053440751665152000000001), true
    assert_equal Prime.probably_prime?(1808422353177349564546512035512530001279481259854248860454348989451026887), true
    assert_equal Prime.probably_prime?(13579111_3151719313_3353739515_3555759717_3757779919_3959799111_1131151171_1913113313_5137139151_1531551571_5917117317_5177179191_1931951971_9931131331_5317319331_3333353373_3935135335_5357359371_3733753773_7939139339_5397399511_5135155175_1953153353_5537539551_5535555575_5957157357_5577579591_5935955975_9971171371_5717719731_7337357377_3975175375_5757759771, 1000), true
    assert_equal Prime.probably_prime?(98765432101456789), true
    assert_equal Prime.probably_prime?(99194853094755497), true
    assert_equal Prime.probably_prime?((10 ** 100) - 1), false
    assert_equal Prime.probably_prime?(2 ** 256), false
    assert_equal Prime.probably_prime?(9 ** 512), false
    assert_equal Prime.probably_prime?(13579111_3151719313_3353739515_3555759717_3757779919_3959799111_1131151171_1913113313_5137139151_1531551571_5917117317_5177179191_1931951971_9931131331_5317319331_3333353373_3935135335_5357359371_3733753773_7939139339_5397399511_5135155175_1953153353_5537539551_5535555575_5957157357_5577579591_5935955975_9971171371_5717719731_7337357377_3975175375_5757759770, 1000), false
  end
end
