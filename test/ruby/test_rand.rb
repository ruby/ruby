# frozen_string_literal: false
require 'test/unit'

class TestRand < Test::Unit::TestCase
  def assert_random_int(m, init = 0, iterate: 5)
    srand(init)
    rnds = [Random.new(init)]
    rnds2 = [rnds[0].dup]
    rnds3 = [rnds[0].dup]
    iterate.times do |i|
      w = rand(m)
      rnds.each do |rnd|
        assert_equal(w, rnd.rand(m))
      end
      rnds2.each do |rnd|
        r=rnd.rand(i...(m+i))
        assert_equal(w+i, r)
      end
      rnds3.each do |rnd|
        r=rnd.rand(i..(m+i-1))
        assert_equal(w+i, r)
      end
      rnds << Marshal.load(Marshal.dump(rnds[-1]))
      rnds2 << Marshal.load(Marshal.dump(rnds2[-1]))
    end
  end

  def test_mt
    assert_random_int(0x100000000, 0x00000456_00000345_00000234_00000123)
  end

  def test_0x3fffffff
    assert_random_int(0x3fffffff)
  end

  def test_0x40000000
    assert_random_int(0x40000000)
  end

  def test_0x40000001
    assert_random_int(0x40000001)
  end

  def test_0xffffffff
    assert_random_int(0xffffffff)
  end

  def test_0x100000000
    assert_random_int(0x100000000)
  end

  def test_0x100000001
    assert_random_int(0x100000001)
  end

  def test_rand_0x100000000
    assert_random_int(0x100000001, 311702798)
  end

  def test_0x1000000000000
    assert_random_int(0x1000000000000)
  end

  def test_0x1000000000001
    assert_random_int(0x1000000000001)
  end

  def test_0x3fffffffffffffff
    assert_random_int(0x3fffffffffffffff)
  end

  def test_0x4000000000000000
    assert_random_int(0x4000000000000000)
  end

  def test_0x4000000000000001
    assert_random_int(0x4000000000000001)
  end

  def test_0x10000000000
    assert_random_int(0x10000000000, 3)
  end

  def test_0x10000
    assert_random_int(0x10000)
  end

  def assert_same_numbers(type, *nums)
    nums.each do |n|
      assert_instance_of(type, n)
    end
    x = nums.shift
    nums.each do |n|
      assert_equal(x, n)
    end
    x
  end

  def test_types
    o = Object.new
    class << o
      def to_int; 100; end
      def class; Integer; end
    end

    srand(0)
    nums = [100.0, (2**100).to_f, (2**100), o, o, o].map do |m|
      k = Integer
      assert_kind_of(k, x = rand(m), m.inspect)
      [m, k, x]
    end
    assert_kind_of(Integer, rand(-(2**100).to_f))

    srand(0)
    rnd = Random.new(0)
    rnd2 = Random.new(0)
    nums.each do |m, k, x|
      assert_same_numbers(m.class, Random.rand(m), rnd.rand(m), rnd2.rand(m))
    end
  end

  def test_srand
    srand
    assert_kind_of(Integer, rand(2))
    assert_kind_of(Integer, Random.new.rand(2))

    srand(2**100)
    rnd = Random.new(2**100)
    r = 3.times.map do
      assert_same_numbers(Integer, rand(0x100000000), rnd.rand(0x100000000))
    end
    srand(2**100)
    r.each do |n|
      assert_same_numbers(Integer, n, rand(0x100000000))
    end
  end

  def test_shuffle
    srand(0)
    result = [*1..5].shuffle
    assert_equal([*1..5], result.sort)
    assert_equal(result, [*1..5].shuffle(random: Random.new(0)))
  end

  def test_big_seed
    assert_random_int(0x100000000, 2**1000000-1)
  end

  def test_random_gc
    r = Random.new(0)
    3.times do
      assert_kind_of(Integer, r.rand(0x100000000))
    end
    GC.start
    3.times do
      assert_kind_of(Integer, r.rand(0x100000000))
    end
  end

  def test_random_type_error
    assert_raise(TypeError) { Random.new(Object.new) }
    assert_raise(TypeError) { Random.new(0).rand(Object.new) }
  end

  def test_random_argument_error
    r = Random.new(0)
    assert_raise(ArgumentError) { r.rand(0, 0) }
    assert_raise(ArgumentError, '[ruby-core:24677]') { r.rand(-1) }
    assert_raise(ArgumentError, '[ruby-core:24677]') { r.rand(-1.0) }
    assert_raise(ArgumentError, '[ruby-core:24677]') { r.rand(0) }
    assert_equal(0, r.rand(1), '[ruby-dev:39166]')
    assert_equal(0, r.rand(0...1), '[ruby-dev:39166]')
    assert_equal(0, r.rand(0..0), '[ruby-dev:39166]')
    assert_equal(0.0, r.rand(0.0..0.0), '[ruby-dev:39166]')
    assert_raise(ArgumentError, '[ruby-dev:39166]') { r.rand(0...0) }
    assert_raise(ArgumentError, '[ruby-dev:39166]') { r.rand(0..-1) }
    assert_raise(ArgumentError, '[ruby-dev:39166]') { r.rand(0.0...0.0) }
    assert_raise(ArgumentError, '[ruby-dev:39166]') { r.rand(0.0...-0.1) }
    bug3027 = '[ruby-core:29075]'
    assert_raise(ArgumentError, bug3027) { r.rand(nil) }
  end

  def test_random_seed
    assert_equal(0, Random.new(0).seed)
    assert_equal(0x100000000, Random.new(0x100000000).seed)
    assert_equal(2**100, Random.new(2**100).seed)
  end

  def test_random_dup
    r1 = Random.new(0)
    r2 = r1.dup
    3.times do
      assert_same_numbers(Integer, r1.rand(0x100000000), r2.rand(0x100000000))
    end
    r2 = r1.dup
    3.times do
      assert_same_numbers(Integer, r1.rand(0x100000000), r2.rand(0x100000000))
    end
  end

  def test_random_bytes
    srand(0)
    r = Random.new(0)

    assert_equal("", r.bytes(0))
    assert_equal("", Random.bytes(0))

    x = r.bytes(1)
    assert_equal(1, x.bytesize)
    assert_equal(x, Random.bytes(1))

    x = r.bytes(10)
    assert_equal(10, x.bytesize)
    assert_equal(x, Random.bytes(10))
  end

  def test_random_range
    srand(0)
    r = Random.new(0)
    now = Time.now
    [5..9, -1000..1000, 2**100+5..2**100+9, 3.1..4, now..(now+2)].each do |range|
      3.times do
        x = rand(range)
        assert_instance_of(range.first.class, x)
        assert_equal(x, r.rand(range))
        assert_include(range, x)
      end
    end
  end

  def test_random_float
    r = Random.new(0)
    3.times do
      assert_include(0...1.0, r.rand)
    end
    [2.0, (2**100).to_f].each do |x|
      range = 0...x
      3.times do
        assert_include(range, r.rand(x), "rand(#{x})")
      end
    end

    assert_raise(Errno::EDOM, Errno::ERANGE) { r.rand(1.0 / 0.0) }
    assert_raise(Errno::EDOM, Errno::ERANGE) { r.rand(0.0 / 0.0) }
    assert_raise(Errno::EDOM) {r.rand(1..)}
    assert_raise(Errno::EDOM) {r.rand(..1)}

    r = Random.new(0)
    [1.0...2.0, 1.0...11.0, 2.0...4.0].each do |range|
      3.times do
        assert_include(range, r.rand(range), "[ruby-core:24655] rand(#{range})")
      end
    end

    assert_nothing_raised {r.rand(-Float::MAX..Float::MAX)}
  end

  def test_random_equal
    r = Random.new(0)
    assert_equal(r, r)
    assert_equal(r, r.dup)
    r1 = r.dup
    r2 = r.dup
    r1.rand(0x100)
    assert_not_equal(r1, r2)
    r2.rand(0x100)
    assert_equal(r1, r2)
  end

  def test_fork_shuffle
    pid = fork do
      (1..10).to_a.shuffle
      raise 'default seed is not set' if srand == 0
    end
    _, st = Process.waitpid2(pid)
    assert_predicate(st, :success?, "#{st.inspect}")
  rescue NotImplementedError, ArgumentError
  end

  def assert_fork_status(n, mesg, &block)
    IO.pipe do |r, w|
      (1..n).map do
        st = desc = nil
        IO.pipe do |re, we|
          p1 = fork {
            re.close
            STDERR.reopen(we)
            w.puts(block.call.to_s)
          }
          we.close
          err = Thread.start {re.read}
          _, st = Process.waitpid2(p1)
          desc = FailDesc[st, mesg, err.value]
        end
        assert(!st.signaled?, desc)
        assert(st.success?, mesg)
        r.gets.strip
      end
    end
  end

  def test_rand_reseed_on_fork
    GC.start
    bug5661 = '[ruby-core:41209]'

    assert_fork_status(1, bug5661) {Random.rand(4)}
    r1, r2 = *assert_fork_status(2, bug5661) {Random.rand}
    assert_not_equal(r1, r2, bug5661)

    assert_fork_status(1, bug5661) {rand(4)}
    r1, r2 = *assert_fork_status(2, bug5661) {rand}
    assert_not_equal(r1, r2, bug5661)

    stable = Random.new
    assert_fork_status(1, bug5661) {stable.rand(4)}
    r1, r2 = *assert_fork_status(2, bug5661) {stable.rand}
    assert_equal(r1, r2, bug5661)

    assert_fork_status(1, '[ruby-core:82100] [Bug #13753]') do
      Random.rand(4)
    end
  rescue NotImplementedError
  end

  def test_seed
    bug3104 = '[ruby-core:29292]'
    rand_1 = Random.new(-1).rand
    assert_not_equal(rand_1, Random.new((1 << 31) -1).rand, "#{bug3104} (2)")
    assert_not_equal(rand_1, Random.new((1 << 63) -1).rand, "#{bug3104} (2)")

    [-1, -2**10, -2**40].each {|n|
      b = (2**64).coerce(n)[0]
      r1 = Random.new(n).rand
      r2 = Random.new(b).rand
      assert_equal(r1, r2)
    }
  end

  def test_seed_leading_zero_guard
    guard = 1<<32
    range = 0...(1<<32)
    all_assertions_foreach(nil, 0, 1, 2) do |i|
      assert_not_equal(Random.new(i).rand(range), Random.new(i+guard).rand(range))
    end
  end

  def test_marshal
    bug3656 = '[ruby-core:31622]'
    assert_raise(TypeError, bug3656) {
      Random.new.__send__(:marshal_load, 0)
    }
  end

  def test_initialize_frozen
    r = Random.new(0)
    r.freeze
    assert_raise(FrozenError, '[Bug #6540]') do
      r.__send__(:initialize, r)
    end
  end

  def test_marshal_load_frozen
    r = Random.new(0)
    d = r.__send__(:marshal_dump)
    r.freeze
    assert_raise(FrozenError, '[Bug #6540]') do
      r.__send__(:marshal_load, d)
    end
  end

  def test_random_ulong_limited
    def (gen = Object.new).rand(*) 1 end
    assert_equal([2], (1..100).map {[1,2,3].sample(random: gen)}.uniq)

    def (gen = Object.new).rand(*) 100 end
    assert_raise_with_message(RangeError, /big 100\z/) {[1,2,3].sample(random: gen)}

    bug7903 = '[ruby-dev:47061] [Bug #7903]'
    def (gen = Object.new).rand(*) -1 end
    assert_raise_with_message(RangeError, /small -1\z/, bug7903) {[1,2,3].sample(random: gen)}

    bug7935 = '[ruby-core:52779] [Bug #7935]'
    class << (gen = Object.new)
      def rand(limit) @limit = limit; 0 end
      attr_reader :limit
    end
    [1, 2].sample(1, random: gen)
    assert_equal(2, gen.limit, bug7935)
  end

  def test_random_ulong_limited_no_rand
    c = Class.new do
      undef rand
      def bytes(n)
        "\0"*n
      end
    end
    gen = c.new.extend(Random::Formatter)
    assert_equal(1, [1, 2].sample(random: gen))
  end

  def test_default_seed
    assert_separately([], "#{<<~"begin;"}\n#{<<~'end;'}")
    begin;
      verbose, $VERBOSE = $VERBOSE, nil
      seed = Random.seed
      rand1 = Random.rand
      $VERBOSE = verbose
      rand2 = Random.new(seed).rand
      assert_equal(rand1, rand2)

      srand seed
      rand3 = rand
      assert_equal(rand1, rand3)
    end;
  end

  def test_urandom
    [0, 1, 100].each do |size|
      v = Random.urandom(size)
      assert_kind_of(String, v)
      assert_equal(size, v.bytesize)
    end
  end

  def test_new_seed
    size = 0
    n = 8
    n.times do
      v = Random.new_seed
      assert_kind_of(Integer, v)
      size += v.size
    end
    # probability of failure <= 1/256**8
    assert_operator(size.fdiv(n), :>, 15)
  end
end
