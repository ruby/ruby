require_relative '../../../spec_helper'
require_relative 'spec_helper'
require_relative 'fixtures/server'

describe "Net::FTP#size" do
  before :each do
    @server = NetFTPSpecs::DummyFTP.new
    @server.serve_once

    @ftp = Net::FTP.new
    @ftp.connect(@server.hostname, @server.server_port)
  end

  after :each do
    @ftp.quit rescue nil
    @ftp.close
    @server.stop
  end

  it "sends the SIZE command to the server" do
    @ftp.size("test.file")
    @ftp.last_response.should == "213 1024\n"
  end

  it "returns the size of the passed file as Integer" do
    @ftp.size("test.file").should eql(1024)
  end

  it "raises a Net::FTPPermError when the response code is 500" do
    @server.should_receive(:size).and_respond("500 Syntax error, command unrecognized.")
    -> { @ftp.size("test.file") }.should raise_error(Net::FTPPermError)
  end

  it "raises a Net::FTPPermError when the response code is 501" do
    @server.should_receive(:size).and_respond("501 Syntax error in parameters or arguments.")
    -> { @ftp.size("test.file") }.should raise_error(Net::FTPPermError)
  end

  it "raises a Net::FTPTempError when the response code is 421" do
    @server.should_receive(:size).and_respond("421 Service not available, closing control connection.")
    -> { @ftp.size("test.file") }.should raise_error(Net::FTPTempError)
  end

  it "raises a Net::FTPPermError when the response code is 550" do
    @server.should_receive(:size).and_respond("550 Requested action not taken.")
    -> { @ftp.size("test.file") }.should raise_error(Net::FTPPermError)
  end
end
