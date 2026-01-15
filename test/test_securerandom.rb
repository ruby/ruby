# frozen_string_literal: false
require 'test/unit'
require 'securerandom'

# This testcase does NOT aim to test cryptographically strongness and randomness.
class TestSecureRandom < Test::Unit::TestCase

  def setup
    @it = SecureRandom
  end

  def test_alphanumeric_with_chars
    assert_nothing_raised(ArgumentError) do
      @it.alphanumeric(1, chars: ("0".."9").to_a)
    end
  end

  # This test took 2 minutes on my machine.
  # And 65536 times loop could not be enough for forcing PID recycle.
  # TODO: We should run this test only on GitHub Actions.
  def test_s_random_bytes_is_fork_safe
    begin
      require 'openssl'
    rescue LoadError
      return
    end
    SecureRandom.random_bytes(8)
    pid, v1 = forking_random_bytes
    assert(check_forking_random_bytes(pid, v1), 'Process ID not recycled?')
  end if false # ENV["CI"] && RUBY_PLATFORM =~ /darwin/ && `sw_vers -productVersion`.to_i > 13 # for Apple Silicon

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
    (65536 * 1.5).to_i.times do
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

  def test_repeated_gen_random
    assert_nothing_raised NoMethodError, '[ruby-core:92633] [Bug #15847]' do
      @it.gen_random(1)
      @it.gen_random(1)
    end
  end
end
