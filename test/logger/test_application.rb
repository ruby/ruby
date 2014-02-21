# coding: US-ASCII
require 'test/unit'
require 'logger'
require 'tempfile'

class TestLoggerApplication < Test::Unit::TestCase
  def setup
    @app = Logger::Application.new('appname')
    @tempfile = Tempfile.new("logger")
    @tempfile.close
    @filename = @tempfile.path
    File.unlink(@filename)
  end

  def teardown
    @tempfile.close(true)
  end

  def test_initialize
    app = Logger::Application.new('appname')
    assert_equal('appname', app.appname)
  end

  def test_start
    @app.set_log(@filename)
    begin
      @app.level = Logger::UNKNOWN
      @app.start # logs FATAL log
      assert_equal(1, File.read(@filename).split(/\n/).size)
    ensure
      @app.logger.close
    end
  end

  def test_logger
    @app.level = Logger::WARN
    @app.set_log(@filename)
    begin
      assert_equal(Logger::WARN, @app.logger.level)
    ensure
      @app.logger.close
    end
    @app.logger = logger = Logger.new(STDOUT)
    assert_equal(logger, @app.logger)
    assert_equal(Logger::WARN, @app.logger.level)
    @app.log = @filename
    begin
      assert(logger != @app.logger)
      assert_equal(Logger::WARN, @app.logger.level)
    ensure
      @app.logger.close
    end
  end
end
