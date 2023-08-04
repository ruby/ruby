require_relative '../../../spec_helper'
require_relative '../fixtures/common'

describe "Logger::LogDevice#close" do
  before :each do
    @file_path = tmp("test_log.log")
    @log_file = File.open(@file_path, "w+")

    # Avoid testing this with STDERR, we don't want to be closing that.
    @device = Logger::LogDevice.new(@log_file)
  end

  after :each do
    @log_file.close unless @log_file.closed?
    rm_r @file_path
  end

  it "closes the LogDevice's stream" do
    @device.close
    -> { @device.write("Test") }.should complain(/\Alog shifting failed\./)
  end
end
