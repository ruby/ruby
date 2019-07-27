require_relative '../../../spec_helper'
require_relative 'spec_helper'
require_relative 'fixtures/server'

describe "Net::FTP#pwd" do
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

  it "sends the PWD command to the server" do
    @ftp.pwd
    @ftp.last_response.should == "257 \"/some/dir/\" - current directory\n"
  end

  it "returns the current directory" do
    @ftp.pwd.should == "/some/dir/"
  end

  it "raises a Net::FTPPermError when the response code is 500" do
    @server.should_receive(:pwd).and_respond("500 Syntax error, command unrecognized.")
    -> { @ftp.pwd }.should raise_error(Net::FTPPermError)
  end

  it "raises a Net::FTPPermError when the response code is 501" do
    @server.should_receive(:pwd).and_respond("501 Syntax error in parameters or arguments.")
    -> { @ftp.pwd }.should raise_error(Net::FTPPermError)
  end

  it "raises a Net::FTPPermError when the response code is 502" do
    @server.should_receive(:pwd).and_respond("502 Command not implemented.")
    -> { @ftp.pwd }.should raise_error(Net::FTPPermError)
  end

  it "raises a Net::FTPTempError when the response code is 421" do
    @server.should_receive(:pwd).and_respond("421 Service not available, closing control connection.")
    -> { @ftp.pwd }.should raise_error(Net::FTPTempError)
  end

  it "raises a Net::FTPPermError when the response code is 550" do
    @server.should_receive(:pwd).and_respond("550 Requested action not taken.")
    -> { @ftp.pwd }.should raise_error(Net::FTPPermError)
  end
end
