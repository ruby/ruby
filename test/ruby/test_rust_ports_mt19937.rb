# frozen_string_literal: false
require 'test/unit'

# Ruby on Rust: the MT19937 core of Random (missing/mt19937.c, compiled
# into random.c: init_genrand, init_by_array, next_state, genrand_int32) is
# ported to core_rs/src/mt19937.rs (port unit mt19937-A-01).
#
# These tests must pass unchanged in both build modes:
#   ./configure                         (Rust ports, USE_RUST_PORTS=1)
#   ./configure --without-rust-ports    (original C, USE_RUST_PORTS=0)
# Expected values are what the original C implementation produces.  The
# 5489 values are also those of the reference MT19937 (mt19937ar.c).
class TestRustPortsMT19937 < Test::Unit::TestCase
  U32 = 2**32

  def draws(rnd, n)
    Array.new(n) { rnd.rand(U32) }
  end

  def test_init_genrand_reference_sequence
    # A one-word seed goes through init_genrand.
    assert_equal([3499211612, 581869302], Random.new(5489).bytes(8).unpack("L<*"))
    assert_equal(2357136044, Random.new(0).rand(U32))
    assert_equal([1608637542, 3421126067, 4083286876, 787846414, 3143890026],
                 draws(Random.new(42), 5))
    assert_equal([327741615, 976413892, 3349725721], draws(Random.new(-7), 3))
  end

  def test_init_by_array_seeds
    # Multi-word seeds go through init_by_array.
    assert_equal([1910715478, 278772827, 1297592944, 2561083672, 2982097399],
                 draws(Random.new(2**100 + 12345), 5))
    # 2**32: two words with the leading-zero guard removed, key_length 1.
    assert_equal([3626764237, 1654615998, 3255389356], draws(Random.new(2**32), 3))
    assert_equal([93740670, 1068495656, 1452108352], draws(Random.new(2**64 - 1), 3))
    # A key longer than the state (key_length > 624).
    assert_equal([629001239, 2764034130, 1718157280], draws(Random.new(1 << 20000), 3))
  end

  def test_next_state_boundaries
    # Crossing the 624-word regeneration boundary several times.
    a = draws(Random.new(12345), 2000)
    assert_equal(4306179229297, a.sum)
    assert_equal([2940097750, 3957348375, 3139197943, 2339195376],
                 [a[623], a[624], a[1247], a[1248]])
  end

  def test_floats_and_bytes
    r = Random.new(3)
    assert_equal(0.5507979025745755, r.rand)
    assert_equal(3, r.rand(100))
    assert_equal("\xB8\xBBxJ\xC8".b, r.bytes(5))
  end

  def test_state_and_left
    r = Random.new(5489)
    dump = r.send(:marshal_dump)
    assert_equal(1, dump[1])  # init_genrand sets left = 1
    assert_equal([5489, 1301868182], [dump[0] & 0xffffffff, (dump[0] >> 32) & 0xffffffff])
    r.rand(U32)
    assert_equal(624, r.send(:marshal_dump)[1])  # next_state sets left = N
    623.times { r.rand(U32) }
    dump = r.send(:marshal_dump)
    assert_equal(1, dump[1])
    assert_equal([2601187879, 3518038711], [dump[0] & 0xffffffff, dump[0] >> (32 * 623)])
    # init_by_array forces state[0] = 0x80000000.
    assert_equal(0x80000000, Random.new(2**100 + 12345).send(:marshal_dump)[0] & 0xffffffff)
  end

  def test_resume_after_marshal_and_dup
    # marshal_load and initialize_copy rebuild `next` from `left`;
    # genrand_int32 must continue from it.
    [0, 1, 300, 623, 624, 625, 1000].each do |skip|
      r = Random.new(777)
      expected = draws(Random.new(777), skip + 700).drop(skip)
      skip.times { r.rand(U32) }
      loaded = Marshal.load(Marshal.dump(r))
      copied = r.dup
      assert_equal(expected, draws(r, 700), "skip=#{skip}")
      assert_equal(expected, draws(loaded, 700), "marshal skip=#{skip}")
      assert_equal(expected, draws(copied, 700), "dup skip=#{skip}")
    end
  end

  def test_srand_matches_random_new
    srand(2024)
    a = Array.new(10) { rand(U32) }
    assert_equal(draws(Random.new(2024), 10), a)
  ensure
    srand
  end
end
