require_relative '../../../spec_helper'
require_relative '../fixtures/common'

describe "Logger#close" do
  before :each do
    @path = tmp("test_log.log")
    @log_file = File.open(@path, "w+")
    @logger = Logger.new(@path)
  end

  after :each do
    @log_file.close unless @log_file.closed?
    rm_r @path
  end

  it "closes the logging device" do
    @logger.close
    lambda { @logger.add(nil, "Foo") }.should complain(/\Alog writing failed\./)
  end
end
