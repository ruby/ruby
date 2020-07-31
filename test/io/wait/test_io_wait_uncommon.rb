# frozen_string_literal: true
require 'test/unit'
require 'io/wait'

# test uncommon device types to check portability problems
# We may optimize IO#wait_*able for non-Linux kernels in the future
class TestIOWaitUncommon < Test::Unit::TestCase
  def test_tty_wait
    begin
      tty = File.open('/dev/tty', 'w+')
    rescue Errno::ENOENT, Errno::ENXIO => e
      skip "/dev/tty: #{e.message} (#{e.class})"
    end
    assert_include [ nil, tty ], tty.wait_readable(0)
    assert_equal tty, tty.wait_writable(1), 'portability test'
  ensure
    tty&.close
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
  def check_dev(dev, m = :wait_readable)
    begin
      fp = File.open("/dev/#{dev}", m == :wait_readable ? 'r' : 'w')
    rescue SystemCallError => e
      skip "#{dev} could not be opened #{e.message} (#{e.class})"
    end
    assert_same fp, fp.__send__(m)
  ensure
    fp&.close
  end

  def test_wait_readable_urandom
    check_dev 'urandom'
  end

  def test_wait_readable_random
    File.open('/dev/random') do |fp|
      assert_nothing_raised do
        fp.wait_readable(0)
      end
    end
  rescue SystemCallError => e
    skip "/dev/random could not be opened #{e.message} (#{e.class})"
  end

  def test_wait_readable_zero
    check_dev 'zero'
  end

  def test_wait_writable_null
    check_dev 'null', :wait_writable
  end
end
