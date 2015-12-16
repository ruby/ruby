# coding: US-ASCII
# frozen_string_literal: false
require 'test/unit'
require 'logger'
require 'tempfile'
require 'tmpdir'

class TestLogDevice < Test::Unit::TestCase
  class LogExcnRaiser
    def write(*arg)
      raise 'disk is full'
    end

    def close
    end

    def stat
      Object.new
    end
  end

  def setup
    @tempfile = Tempfile.new("logger")
    @tempfile.close
    @filename = @tempfile.path
    File.unlink(@filename)
  end

  def teardown
    @tempfile.close(true)
  end

  def d(log, opt = {})
    Logger::LogDevice.new(log, opt)
  end

  def test_initialize
    logdev = d(STDERR)
    assert_equal(STDERR, logdev.dev)
    assert_nil(logdev.filename)
    assert_raise(TypeError) do
      d(nil)
    end
    #
    logdev = d(@filename)
    begin
      assert(File.exist?(@filename))
      assert(logdev.dev.sync)
      assert_equal(@filename, logdev.filename)
      logdev.write('hello')
    ensure
      logdev.close
    end
    # create logfile whitch is already exist.
    logdev = d(@filename)
    begin
      logdev.write('world')
      logfile = File.read(@filename)
      assert_equal(2, logfile.split(/\n/).size)
      assert_match(/^helloworld$/, logfile)
    ensure
      logdev.close
    end
  end

  def test_write
    r, w = IO.pipe
    logdev = d(w)
    logdev.write("msg2\n\n")
    IO.select([r], nil, nil, 0.1)
    w.close
    msg = r.read
    r.close
    assert_equal("msg2\n\n", msg)
    #
    logdev = d(LogExcnRaiser.new)
    class << (stderr = '')
      alias write <<
    end
    $stderr, stderr = stderr, $stderr
    begin
      assert_nothing_raised do
        logdev.write('hello')
      end
    ensure
      logdev.close
      $stderr, stderr = stderr, $stderr
    end
    assert_equal "log writing failed. disk is full\n", stderr
  end

  def test_close
    r, w = IO.pipe
    logdev = d(w)
    logdev.write("msg2\n\n")
    IO.select([r], nil, nil, 0.1)
    assert(!w.closed?)
    logdev.close
    assert(w.closed?)
    r.close
  end

  def test_reopen_io
    logdev  = d(STDERR)
    old_dev = logdev.dev
    logdev.reopen
    assert_equal(STDERR, logdev.dev)
    assert(!old_dev.closed?)
  end

  def test_reopen_io_by_io
    logdev  = d(STDERR)
    old_dev = logdev.dev
    logdev.reopen(STDOUT)
    assert_equal(STDOUT, logdev.dev)
    assert(!old_dev.closed?)
  end

  def test_reopen_io_by_file
    logdev  = d(STDERR)
    old_dev = logdev.dev
    logdev.reopen(@filename)
    begin
      assert(File.exist?(@filename))
      assert_equal(@filename, logdev.filename)
      assert(!old_dev.closed?)
    ensure
      logdev.close
    end
  end

  def test_reopen_file
    logdev = d(@filename)
    old_dev = logdev.dev

    logdev.reopen
    begin
      assert(File.exist?(@filename))
      assert_equal(@filename, logdev.filename)
      assert(old_dev.closed?)
    ensure
      logdev.close
    end
  end

  def test_reopen_file_by_io
    logdev = d(@filename)
    old_dev = logdev.dev
    logdev.reopen(STDOUT)
    assert_equal(STDOUT, logdev.dev)
    assert_nil(logdev.filename)
    assert(old_dev.closed?)
  end

  def test_reopen_file_by_file
    logdev = d(@filename)
    old_dev = logdev.dev

    tempfile2 = Tempfile.new("logger")
    tempfile2.close
    filename2 = tempfile2.path
    File.unlink(filename2)

    logdev.reopen(filename2)
    begin
      assert(File.exist?(filename2))
      assert_equal(filename2, logdev.filename)
      assert(old_dev.closed?)
    ensure
      logdev.close
      tempfile2.close(true)
    end
  end

  def test_shifting_size
    tmpfile = Tempfile.new([File.basename(__FILE__, '.*'), '_1.log'])
    logfile = tmpfile.path
    logfile0 = logfile + '.0'
    logfile1 = logfile + '.1'
    logfile2 = logfile + '.2'
    logfile3 = logfile + '.3'
    tmpfile.close(true)
    File.unlink(logfile) if File.exist?(logfile)
    File.unlink(logfile0) if File.exist?(logfile0)
    File.unlink(logfile1) if File.exist?(logfile1)
    File.unlink(logfile2) if File.exist?(logfile2)
    logger = Logger.new(logfile, 4, 100)
    logger.error("0" * 15)
    assert(File.exist?(logfile))
    assert(!File.exist?(logfile0))
    logger.error("0" * 15)
    assert(File.exist?(logfile0))
    assert(!File.exist?(logfile1))
    logger.error("0" * 15)
    assert(File.exist?(logfile1))
    assert(!File.exist?(logfile2))
    logger.error("0" * 15)
    assert(File.exist?(logfile2))
    assert(!File.exist?(logfile3))
    logger.error("0" * 15)
    assert(!File.exist?(logfile3))
    logger.error("0" * 15)
    assert(!File.exist?(logfile3))
    logger.close
    File.unlink(logfile)
    File.unlink(logfile0)
    File.unlink(logfile1)
    File.unlink(logfile2)

    tmpfile = Tempfile.new([File.basename(__FILE__, '.*'), '_2.log'])
    logfile = tmpfile.path
    logfile0 = logfile + '.0'
    logfile1 = logfile + '.1'
    logfile2 = logfile + '.2'
    logfile3 = logfile + '.3'
    tmpfile.close(true)
    logger = Logger.new(logfile, 4, 150)
    logger.error("0" * 15)
    assert(File.exist?(logfile))
    assert(!File.exist?(logfile0))
    logger.error("0" * 15)
    assert(!File.exist?(logfile0))
    logger.error("0" * 15)
    assert(File.exist?(logfile0))
    assert(!File.exist?(logfile1))
    logger.error("0" * 15)
    assert(!File.exist?(logfile1))
    logger.error("0" * 15)
    assert(File.exist?(logfile1))
    assert(!File.exist?(logfile2))
    logger.error("0" * 15)
    assert(!File.exist?(logfile2))
    logger.error("0" * 15)
    assert(File.exist?(logfile2))
    assert(!File.exist?(logfile3))
    logger.error("0" * 15)
    assert(!File.exist?(logfile3))
    logger.error("0" * 15)
    assert(!File.exist?(logfile3))
    logger.error("0" * 15)
    assert(!File.exist?(logfile3))
    logger.close
    File.unlink(logfile)
    File.unlink(logfile0)
    File.unlink(logfile1)
    File.unlink(logfile2)
  end

  def test_shifting_age_variants
    logger = Logger.new(@filename, 'daily')
    logger.info('daily')
    logger.close
    logger = Logger.new(@filename, 'weekly')
    logger.info('weekly')
    logger.close
    logger = Logger.new(@filename, 'monthly')
    logger.info('monthly')
    logger.close
  end

  def test_shifting_age
    # shift_age other than 'daily', 'weekly', and 'monthly' means 'everytime'
    yyyymmdd = Time.now.strftime("%Y%m%d")
    filename1 = @filename + ".#{yyyymmdd}"
    filename2 = @filename + ".#{yyyymmdd}.1"
    filename3 = @filename + ".#{yyyymmdd}.2"
    begin
      logger = Logger.new(@filename, 'now')
      assert(File.exist?(@filename))
      assert(!File.exist?(filename1))
      assert(!File.exist?(filename2))
      assert(!File.exist?(filename3))
      logger.info("0" * 15)
      assert(File.exist?(@filename))
      assert(File.exist?(filename1))
      assert(!File.exist?(filename2))
      assert(!File.exist?(filename3))
      logger.warn("0" * 15)
      assert(File.exist?(@filename))
      assert(File.exist?(filename1))
      assert(File.exist?(filename2))
      assert(!File.exist?(filename3))
      logger.error("0" * 15)
      assert(File.exist?(@filename))
      assert(File.exist?(filename1))
      assert(File.exist?(filename2))
      assert(File.exist?(filename3))
    ensure
      logger.close if logger
      [filename1, filename2, filename3].each do |filename|
        File.unlink(filename) if File.exist?(filename)
      end
    end
  end

  def test_shifting_size_in_multiprocess
    tmpfile = Tempfile.new([File.basename(__FILE__, '.*'), '_1.log'])
    logfile = tmpfile.path
    logfile0 = logfile + '.0'
    logfile1 = logfile + '.1'
    logfile2 = logfile + '.2'
    tmpfile.close(true)
    File.unlink(logfile) if File.exist?(logfile)
    File.unlink(logfile0) if File.exist?(logfile0)
    File.unlink(logfile1) if File.exist?(logfile1)
    File.unlink(logfile2) if File.exist?(logfile2)
    begin
      stderr = run_children(2, [logfile], <<-'END')
        logger = Logger.new(ARGV[0], 4, 10)
        10.times do
          logger.info '0' * 15
        end
      END
      assert_no_match(/log shifting failed/, stderr)
      assert_no_match(/log writing failed/, stderr)
      assert_no_match(/log rotation inter-process lock failed/, stderr)
    ensure
      File.unlink(logfile) if File.exist?(logfile)
      File.unlink(logfile0) if File.exist?(logfile0)
      File.unlink(logfile1) if File.exist?(logfile1)
      File.unlink(logfile2) if File.exist?(logfile2)
    end
  end

  def test_shifting_age_in_multiprocess
    yyyymmdd = Time.now.strftime("%Y%m%d")
    begin
      stderr = run_children(2, [@filename], <<-'END')
        logger = Logger.new(ARGV[0], 'now')
        10.times do
          logger.info '0' * 15
        end
      END
      assert_no_match(/log shifting failed/, stderr)
      assert_no_match(/log writing failed/, stderr)
      assert_no_match(/log rotation inter-process lock failed/, stderr)
    ensure
      Dir.glob("#{@filename}.#{yyyymmdd}{,.[1-9]*}") do |filename|
        File.unlink(filename) if File.exist?(filename)
      end
    end
  end

  def test_open_logfile_in_multiprocess
    tmpfile = Tempfile.new([File.basename(__FILE__, '.*'), '_1.log'])
    logfile = tmpfile.path
    tmpfile.close(true)
    begin
      20.times do
        run_children(2, [logfile], <<-'END')
          logfile = ARGV[0]
          logdev = Logger::LogDevice.new(logfile)
          logdev.send(:open_logfile, logfile)
        END
        assert_equal(1, File.readlines(logfile).grep(/# Logfile created on/).size)
        File.unlink(logfile)
      end
    ensure
      File.unlink(logfile) if File.exist?(logfile)
    end
  end

  def test_shifting_size_not_rotate_too_much
    logdev0 = d(@filename)
    logdev0.__send__(:add_log_header, @tempfile)
    header_size = @tempfile.size
    message = "*" * 99 + "\n"
    shift_size = header_size + message.size * 3 - 1
    opt = {shift_age: 1, shift_size: shift_size}

    Dir.mktmpdir do |tmpdir|
      begin
        log = File.join(tmpdir, "log")
        logdev1 = d(log, opt)
        logdev2 = d(log, opt)

        assert_file.identical?(log, logdev1.dev)
        assert_file.identical?(log, logdev2.dev)

        3.times{logdev1.write(message)}
        assert_file.identical?(log, logdev1.dev)
        assert_file.identical?(log, logdev2.dev)

        logdev1.write(message)
        assert_file.identical?(log, logdev1.dev)
        assert_file.identical?(log + ".0", logdev2.dev)

        logdev2.write(message)
        assert_file.identical?(log, logdev1.dev)
        assert_file.identical?(log, logdev2.dev)

        logdev1.write(message)
        assert_file.identical?(log, logdev1.dev)
        assert_file.identical?(log, logdev2.dev)
      ensure
        logdev1.close if logdev1
        logdev2.close if logdev2
      end
    end
  ensure
    logdev0.close
  end unless /mswin|mingw/ =~ RUBY_PLATFORM

  def test_shifting_midnight
    Dir.mktmpdir do |tmpdir|
      assert_in_out_err([*%W"--disable=gems -rlogger -C#{tmpdir} -"], <<-'end;')
        begin
          module FakeTime
            attr_accessor :now
          end

          class << Time
            prepend FakeTime
          end

          log = "log"
          File.open(log, "w") {}
          File.utime(*[Time.mktime(2014, 1, 1, 23, 59, 59)]*2, log)

          Time.now = Time.mktime(2014, 1, 2, 23, 59, 59, 999000)
          dev = Logger::LogDevice.new(log, shift_age: 'daily')
          dev.write("#{Time.now} hello-1\n")

          Time.now = Time.mktime(2014, 1, 3, 1, 1, 1)
          dev.write("#{Time.now} hello-2\n")
        ensure
          dev.close
        end
      end;

      bug = '[GH-539]'
      log = File.join(tmpdir, "log")
      cont = File.read(log)
      assert_match(/hello-2/, cont)
      assert_not_match(/hello-1/, cont)
      assert_file.for(bug).exist?(log+".20140102")
      assert_match(/hello-1/, File.read(log+".20140102"), bug)
    end
  end

  env_tz_works = /linux|darwin|freebsd/ =~ RUBY_PLATFORM # borrow from test/ruby/test_time_tz.rb

  def test_shifting_weekly
    Dir.mktmpdir do |tmpdir|
      assert_in_out_err([{"TZ"=>"UTC"}, *%W"-rlogger -C#{tmpdir} -"], <<-'end;')
        begin
          module FakeTime
            attr_accessor :now
          end

          class << Time
            prepend FakeTime
          end

          log = "log"
          File.open(log, "w") {}

          Time.now = Time.utc(2015, 12, 14, 0, 1, 1)
          dev = Logger::LogDevice.new("log", shift_age: 'weekly')

          Time.now = Time.utc(2015, 12, 19, 12, 34, 56)
          dev.write("#{Time.now} hello-1\n")
          File.utime(Time.now, Time.now, log)

          Time.now = Time.utc(2015, 12, 20, 0, 1, 1)
          File.utime(Time.now, Time.now, log)
          dev.write("#{Time.now} hello-2\n")
        ensure
          dev.close if dev
        end
      end;
      log = File.join(tmpdir, "log")
      cont = File.read(log)
      assert_match(/hello-2/, cont)
      assert_not_match(/hello-1/, cont)
      log = Dir.glob(log+".*")
      assert_equal(1, log.size)
      log, = *log
      cont = File.read(log)
      assert_match(/hello-1/, cont)
      assert_equal("2015-12-19", cont[/^[-\d]+/])
      assert_equal("20151219", log[/\d+\z/])
    end
  end if env_tz_works

  def test_shifting_dst_change
    Dir.mktmpdir do |tmpdir|
      assert_in_out_err([{"TZ"=>"Europe/London"}, *%W"--disable=gems -rlogger -C#{tmpdir} -"], <<-'end;')
        begin
          module FakeTime
            attr_accessor :now
          end

          class << Time
            prepend FakeTime
          end

          log = "log"
          File.open(log, "w") {}

          Time.now = Time.mktime(2014, 3, 30, 0, 1, 1)
          File.utime(Time.now, Time.now, log)

          dev = Logger::LogDevice.new(log, shift_age: 'daily')
          dev.write("#{Time.now} hello-1\n")
          File.utime(*[Time.mktime(2014, 3, 30, 0, 2, 3)]*2, log)

          Time.now = Time.mktime(2014, 3, 31, 0, 1, 1)
          File.utime(Time.now, Time.now, log)
          dev.write("#{Time.now} hello-2\n")
        ensure
          dev.close
        end
      end;

      log = File.join(tmpdir, "log")
      cont = File.read(log)
      assert_match(/hello-2/, cont)
      assert_not_match(/hello-1/, cont)
      assert_file.exist?(log+".20140330")
    end
  end if env_tz_works

  def test_shifting_weekly_dst_change
    Dir.mktmpdir do |tmpdir|
      assert_separately([{"TZ"=>"Europe/London"}, *%W"-rlogger -C#{tmpdir} -"], <<-'end;')
        begin
          module FakeTime
            attr_accessor :now
          end

          class << Time
            prepend FakeTime
          end

          log = "log"
          File.open(log, "w") {}

          Time.now = Time.mktime(2015, 10, 25, 0, 1, 1)
          dev = Logger::LogDevice.new("log", shift_age: 'weekly')
          dev.write("#{Time.now} hello-1\n")
        ensure
          dev.close if dev
        end
      end;
      log = File.join(tmpdir, "log")
      cont = File.read(log)
      assert_match(/hello-1/, cont)
    end
  end if env_tz_works

  private

  def run_children(n, args, src)
    r, w = IO.pipe
    [w, *(1..n).map do
       f = IO.popen([EnvUtil.rubybin, *%w[--disable=gems -rlogger -], *args], "w", err: w)
       f.puts(src)
       f
     end].each(&:close)
    stderr = r.read
    r.close
    stderr
  end
end
