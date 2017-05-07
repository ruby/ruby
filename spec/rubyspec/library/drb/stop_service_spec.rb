require File.expand_path('../../../spec_helper', __FILE__)
require File.expand_path('../fixtures/test_server', __FILE__)
require 'drb'

describe "DRb.stop_service" do
  before :all do
    # for concurrent processes
    @port = 9001 + (Process.pid & 7 )
  end

  before :each do
    # because each spec needs it's own port since DRb is broken that way as exhibited below
    @url = "druby://localhost:#{@port}"
    @port += 1
  end

  it "clears the port so a new server can start" do
    10.times do
      server = nil
      lambda { server = DRb.start_service(@url, TestServer.new) }.should_not raise_error
      DRb.current_server.should == server
      lambda { DRb.stop_service }.should_not raise_error
    end
  end
end
