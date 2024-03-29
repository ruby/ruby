require_relative '../../spec_helper'
require_relative 'spec_helper'
require_relative 'fixtures/server'

describe "Net::FTP#status" do
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

  it "sends the STAT command to the server" do
    @ftp.status
    @ftp.last_response.should == "211 System status, or system help reply. (STAT)\n"
  end

  it "sends the STAT command with an optional parameter to the server" do
    @ftp.status("/pub").should == "211 System status, or system help reply. (STAT /pub)\n"
  end

  it "returns the received information" do
    @ftp.status.should == "211 System status, or system help reply. (STAT)\n"
  end

  it "does not raise an error when the response code is 212" do
    @server.should_receive(:stat).and_respond("212 Directory status.")
    -> { @ftp.status }.should_not raise_error
  end

  it "does not raise an error when the response code is 213" do
    @server.should_receive(:stat).and_respond("213 File status.")
    -> { @ftp.status }.should_not raise_error
  end

  it "raises a Net::FTPPermError when the response code is 500" do
    @server.should_receive(:stat).and_respond("500 Syntax error, command unrecognized.")
    -> { @ftp.status }.should raise_error(Net::FTPPermError)
  end

  it "raises a Net::FTPPermError when the response code is 501" do
    @server.should_receive(:stat).and_respond("501 Syntax error in parameters or arguments.")
    -> { @ftp.status }.should raise_error(Net::FTPPermError)
  end

  it "raises a Net::FTPPermError when the response code is 502" do
    @server.should_receive(:stat).and_respond("502 Command not implemented.")
    -> { @ftp.status }.should raise_error(Net::FTPPermError)
  end

  it "raises a Net::FTPTempError when the response code is 421" do
    @server.should_receive(:stat).and_respond("421 Service not available, closing control connection.")
    -> { @ftp.status }.should raise_error(Net::FTPTempError)
  end

  it "raises a Net::FTPPermError when the response code is 530" do
    @server.should_receive(:stat).and_respond("530 Requested action not taken.")
    -> { @ftp.status }.should raise_error(Net::FTPPermError)
  end
end
