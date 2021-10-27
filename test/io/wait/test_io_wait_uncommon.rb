# frozen_string_literal: true
require 'test/unit'
require 'io/wait'

# test uncommon device types to check portability problems
# We may optimize IO#wait_*able for non-Linux kernels in the future
class TestIOWaitUncommon < Test::Unit::TestCase
  def test_tty_wait
    check_dev('/dev/tty', mode: 'w+') do |tty|
      assert_include [ nil, tty ], tty.wait_readable(0)
      assert_equal tty, tty.wait_writable(1), 'portability test'
    end
  end

  def test_fifo_wait
    skip 'no mkfifo' unless File.respond_to?(:mkfifo) && IO.const_defined?(:NONBLOCK)
    require 'tmpdir'
    Dir.mktmpdir('rubytest-fifo') do |dir|
      fifo = "#{dir}/fifo"
      assert_equal 0, File.mkfifo(fifo)
      rd = Thread.new { File.open(fifo, IO::RDONLY|IO::NONBLOCK) }
      begin
        wr = File.open(fifo, IO::WRONLY|IO::NONBLOCK)
      rescue Errno::ENXIO
        Thread.pass
      end until wr
      assert_instance_of File, rd.value
      assert_instance_of File, wr
      rd = rd.value
      assert_nil rd.wait_readable(0)
      assert_same wr, wr.wait_writable(0)
      wr.syswrite 'hi'
      assert_same rd, rd.wait_readable(1)
      wr.close
      assert_equal 'hi', rd.gets
      rd.close
    end
  end

  # used to find portability problems because some ppoll implementations
  # are incomplete and do not work for certain "file" types
  def check_dev(dev, m = :wait_readable, mode: m == :wait_readable ? 'r' : 'w', &block)
    begin
      fp = File.open(dev, mode)
    rescue Errno::ENOENT
      return # Ignore silently
    rescue SystemCallError => e
      skip "#{dev} could not be opened #{e.message} (#{e.class})"
    end
    if block
      yield fp
    else
      assert_same fp, fp.__send__(m)
    end
  ensure
    fp&.close
  end

  def test_wait_readable_urandom
    check_dev('/dev/urandom')
  end

  def test_wait_readable_random
    check_dev('/dev/random') do |fp|
      assert_nothing_raised do
        fp.wait_readable(0)
      end
    end
  end

  def test_wait_readable_zero
    check_dev('/dev/zero')
  end

  def test_wait_writable_null
    check_dev(IO::NULL, :wait_writable)
  end
end
