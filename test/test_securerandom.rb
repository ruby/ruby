# frozen_string_literal: false
require 'test/unit'
require 'securerandom'
require 'tempfile'

# This testcase does NOT aim to test cryptographically strongness and randomness.
class TestSecureRandom < Test::Unit::TestCase
  def setup
    @it = SecureRandom
  end

  def test_s_random_bytes
    assert_equal(16, @it.random_bytes.size)
    assert_equal(Encoding::ASCII_8BIT, @it.random_bytes.encoding)
    65.times do |idx|
      assert_equal(idx, @it.random_bytes(idx).size)
    end
  end

# This test took 2 minutes on my machine.
# And 65536 times loop could not be enough for forcing PID recycle.
if false
  def test_s_random_bytes_is_fork_safe
    begin
      require 'openssl'
    rescue LoadError
      return
    end
    SecureRandom.random_bytes(8)
    pid, v1 = forking_random_bytes
    assert(check_forking_random_bytes(pid, v1), 'Process ID not recycled?')
  end

  def forking_random_bytes
    r, w = IO.pipe
    pid = fork {
      r.close
      w.write SecureRandom.random_bytes(8)
      w.close
    }
    w.close
    v = r.read(8)
    r.close
    Process.waitpid2(pid)
    [pid, v]
  end

  def check_forking_random_bytes(target_pid, target)
    65536.times do
      pid = fork {
        if $$ == target_pid
          v2 = SecureRandom.random_bytes(8)
          if v2 == target
            exit(1)
          else
            exit(2)
          end
        end
        exit(3)
      }
      pid, status = Process.waitpid2(pid)
      case status.exitstatus
      when 1
        raise 'returned same sequence for same PID'
      when 2
        return true
      end
    end
    false # not recycled?
  end
end

  def test_s_hex
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

  def test_s_base64
    assert_equal(16, @it.base64.unpack('m*')[0].size)
    17.times do |idx|
      assert_equal(idx, @it.base64(idx).unpack('m*')[0].size)
    end
  end

  def test_s_urlsafe_base64
    safe = /[\n+\/]/
    65.times do |idx|
      assert_not_match(safe, @it.urlsafe_base64(idx))
    end
    # base64 can include unsafe byte
    assert((0..10000).any? {|idx| safe =~ @it.base64(idx)}, "None of base64(0..10000) is url-safe")
  end

  def test_s_random_number_float
    101.times do
      v = @it.random_number
      assert_in_range(0.0...1.0, v)
    end
  end

  def test_s_random_number_float_by_zero
    101.times do
      v = @it.random_number(0)
      assert_in_range(0.0...1.0, v)
    end
  end

  def test_s_random_number_int
    101.times do |idx|
      next if idx.zero?
      v = @it.random_number(idx)
      assert_in_range(0...idx, v)
    end
  end

  def test_s_random_number_not_default
    msg = "SecureRandom#random_number should not be affected by srand"
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

  def test_uuid
    uuid = @it.uuid
    assert_equal(36, uuid.size)
    assert_match(/\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/, uuid)
  end

  def protect
    begin
      yield
    rescue NotImplementedError
      # ignore
    end
  end

  def remove_feature(basename)
    $LOADED_FEATURES.delete_if { |path|
      if File.basename(path) == basename
        $LOAD_PATH.any? { |dir|
          File.exist?(File.join(dir, basename))
        }
      end
    }
  end

  def assert_in_range(range, result, mesg = nil)
    assert(range.cover?(result), message(mesg) {"Expected #{result} to be in #{range}"})
  end

  def test_with_openssl
    begin
      require 'openssl'
    rescue LoadError
      return
    end
    assert_equal(Encoding::ASCII_8BIT, @it.send(:gen_random_openssl, 16).encoding)
    65.times do |idx|
      assert_equal(idx, @it.send(:gen_random_openssl, idx).size)
    end
  end
end
