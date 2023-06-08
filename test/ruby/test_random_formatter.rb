require 'test/unit'
require 'random/formatter'

module Random::Formatter
  module FormatterTest
    def test_random_bytes
      assert_equal(16, @it.random_bytes.size)
      assert_equal(Encoding::ASCII_8BIT, @it.random_bytes.encoding)
      65.times do |idx|
        assert_equal(idx, @it.random_bytes(idx).size)
      end
    end

    def test_hex
      s = @it.hex
      assert_equal(16 * 2, s.size)
      assert_match(/\A\h+\z/, s)
      33.times do |idx|
        s = @it.hex(idx)
        assert_equal(idx * 2, s.size)
        assert_match(/\A\h*\z/, s)
      end
    end

    def test_hex_encoding
      assert_equal(Encoding::US_ASCII, @it.hex.encoding)
    end

    def test_base64
      assert_equal(16, @it.base64.unpack1('m*').size)
      17.times do |idx|
        assert_equal(idx, @it.base64(idx).unpack1('m*').size)
      end
    end

    def test_urlsafe_base64
      safe = /[\n+\/]/
      65.times do |idx|
        assert_not_match(safe, @it.urlsafe_base64(idx))
      end
      # base64 can include unsafe byte
      assert((0..10000).any? {|idx| safe =~ @it.base64(idx)}, "None of base64(0..10000) is url-safe")
    end

    def test_random_number_float
      101.times do
        v = @it.random_number
        assert_in_range(0.0...1.0, v)
      end
    end

    def test_random_number_float_by_zero
      101.times do
        v = @it.random_number(0)
        assert_in_range(0.0...1.0, v)
      end
    end

    def test_random_number_int
      101.times do |idx|
        next if idx.zero?
        v = @it.random_number(idx)
        assert_in_range(0...idx, v)
      end
    end

    def test_uuid
      uuid = @it.uuid
      assert_equal(36, uuid.size)

      # Check time_hi_and_version and clock_seq_hi_res bits (RFC 4122 4.4)
      assert_equal('4', uuid[14])
      assert_include(%w'8 9 a b', uuid[19])

      assert_match(/\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/, uuid)
    end

    def test_uuid_v7
      t1 = Time.now(in: "Z").floor(3)
      uuid = @it.uuid_v7
      t3 = Time.now(in: "Z").floor(3)

      assert_match(/\A\h{8}-\h{4}-7\h{3}-[89ab]\h{3}-\h{12}\z/, uuid)

      t2 = (Integer("0x#{uuid[0..7]}#{uuid[9..12]}") / 1000r)
        .then { Time.at(_1, in: "Z") }
      assert_operator(t1, :<=, t2)
      assert_operator(t2, :<=, t3)
    end

    def test_uuid_v7_extra_timestamp_bits
      t1 = Time.now(in: "Z").floor(6)
      uuid = @it.uuid_v7(extra_timestamp_bit_count: 12)
      t3 = Time.now(in: "Z").floor(6)

      assert_match(/\A\h{8}-\h{4}-7\h{3}-[89ab]\h{3}-\h{12}\z/, uuid)

      t2 = ((Integer("0x#{uuid[0..7]}#{uuid[9..12]}") / 1000r) +
            Integer("0x#{uuid[15..17]}") / 4_096_000r)
        .then { Time.at(_1, in: "Z") }
      assert_operator(t1, :<=, t2)
      assert_operator(t2, :<=, t3)
    end

    def test_alphanumeric
      65.times do |n|
        an = @it.alphanumeric(n)
        assert_match(/\A[0-9a-zA-Z]*\z/, an)
        assert_equal(n, an.length)
      end
    end

    def assert_in_range(range, result, mesg = nil)
      assert(range.cover?(result), build_message(mesg, "Expected #{result} to be in #{range}"))
    end
  end

  module NotDefaultTest
    def test_random_number_not_default
      msg = "random_number should not be affected by srand"
      seed = srand(0)
      x = @it.random_number(1000)
      10.times do|i|
        srand(0)
        return unless @it.random_number(1000) == x
      end
      srand(0)
      assert_not_equal(x, @it.random_number(1000), msg)
    ensure
      srand(seed) if seed
    end
  end

  class TestClassMethods < Test::Unit::TestCase
    include FormatterTest

    def setup
      @it = Random
    end
  end

  class TestInstanceMethods < Test::Unit::TestCase
    include FormatterTest
    include NotDefaultTest

    def setup
      @it = Random.new
    end
  end
end
