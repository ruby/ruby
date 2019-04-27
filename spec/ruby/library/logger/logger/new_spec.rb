require_relative '../../../spec_helper'
require_relative '../fixtures/common'

describe "Logger#new" do

  before :each do
    @file_path = tmp("test_log.log")
    @log_file = File.open(@file_path, "w+")
  end

  after :each do
    @log_file.close unless @log_file.closed?
    rm_r @file_path
  end

   it "creates a new logger object" do
     l = Logger.new(STDERR)
     lambda { l.add(Logger::WARN, "Foo") }.should output_to_fd(/Foo/, STDERR)
   end

   it "receives a logging device as first argument" do
     l = Logger.new(@log_file)
     l.add(Logger::WARN, "Test message")

     @log_file.rewind
     LoggerSpecs.strip_date(@log_file.readline).should == "WARN -- : Test message\n"
     l.close
   end

  it "receives a frequency rotation as second argument" do
     lambda { Logger.new(@log_file, "daily") }.should_not raise_error
     lambda { Logger.new(@log_file, "weekly") }.should_not raise_error
     lambda { Logger.new(@log_file, "monthly") }.should_not raise_error
  end

  it "also receives a number of log files to keep as second argument" do
    lambda { Logger.new(@log_file, 1).close }.should_not raise_error
  end

  it "receives a maximum logfile size as third argument" do
    # This should create 2 small log files, logfile_test and logfile_test.0
    # in /tmp, each one with a different message.
    path = tmp("logfile_test.log")

    l = Logger.new(path, 2, 5)
    l.add Logger::WARN, "foo"
    l.add Logger::WARN, "bar"

    File.exist?(path).should be_true
    File.exist?(path + ".0").should be_true

    # first line will be a comment so we'll have to skip it.
    f = File.open(path)
    f1 = File.open("#{path}.0")
    LoggerSpecs.strip_date(f1.readlines.last).should == "WARN -- : foo\n"
    LoggerSpecs.strip_date(f.readlines.last).should == "WARN -- : bar\n"

    l.close
    f.close
    f1.close
    rm_r path, "#{path}.0"
  end

  it "receives level symbol as keyword argument" do
    logger = Logger.new(STDERR, level: :info)
    logger.level.should == Logger::INFO
  end

  it "receives level as keyword argument" do
    logger = Logger.new(STDERR, level: Logger::INFO)
    logger.level.should == Logger::INFO
  end

  it "receives progname as keyword argument" do
    progname = "progname"

    logger = Logger.new(STDERR, progname: progname)
    logger.progname.should == progname
  end

  it "receives datetime_format as keyword argument" do
    datetime_format = "%H:%M:%S"

    logger = Logger.new(STDERR, datetime_format: datetime_format)
    logger.datetime_format.should == datetime_format
  end

  it "receives formatter as keyword argument" do
    formatter = Class.new do
      def call(_severity, _time, _progname, _msg); end
    end.new

    logger = Logger.new(STDERR, formatter: formatter)
    logger.formatter.should == formatter
  end

  it "receives shift_period_suffix " do
    shift_period_suffix = "%Y-%m-%d"
    path                = tmp("shift_period_suffix_test.log")
    now                 = Time.now
    tomorrow            = Time.at(now.to_i + 60 * 60 * 24)
    logger              = Logger.new(path, 'daily', shift_period_suffix: shift_period_suffix)

    logger.add Logger::INFO, 'message'

    Time.stub!(:now).and_return(tomorrow)
    logger.add Logger::INFO, 'second message'

    shifted_path = "#{path}.#{now.strftime(shift_period_suffix)}"

    File.exist?(shifted_path).should == true

    logger.close

    rm_r path, shifted_path
  end

end
