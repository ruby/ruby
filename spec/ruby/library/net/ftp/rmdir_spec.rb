require_relative '../../../spec_helper'
require_relative 'spec_helper'
require_relative 'fixtures/server'

describe "Net::FTP#rmdir" do
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

  it "sends the RMD command with the passed pathname to the server" do
    @ftp.rmdir("test.folder")
    @ftp.last_response.should == "250 Requested file action okay, completed. (RMD test.folder)\n"
  end

  it "returns nil" do
    @ftp.rmdir("test.folder").should be_nil
  end

  it "raises a Net::FTPPermError when the response code is 500" do
    @server.should_receive(:rmd).and_respond("500 Syntax error, command unrecognized.")
    -> { @ftp.rmdir("test.folder") }.should raise_error(Net::FTPPermError)
  end

  it "raises a Net::FTPPermError when the response code is 501" do
    @server.should_receive(:rmd).and_respond("501 Syntax error in parameters or arguments.")
    -> { @ftp.rmdir("test.folder") }.should raise_error(Net::FTPPermError)
  end

  it "raises a Net::FTPPermError when the response code is 502" do
    @server.should_receive(:rmd).and_respond("502 Command not implemented.")
    -> { @ftp.rmdir("test.folder") }.should raise_error(Net::FTPPermError)
  end

  it "raises a Net::FTPTempError when the response code is 421" do
    @server.should_receive(:rmd).and_respond("421 Service not available, closing control connection.")
    -> { @ftp.rmdir("test.folder") }.should raise_error(Net::FTPTempError)
  end

  it "raises a Net::FTPPermError when the response code is 530" do
    @server.should_receive(:rmd).and_respond("530 Not logged in.")
    -> { @ftp.rmdir("test.folder") }.should raise_error(Net::FTPPermError)
  end

  it "raises a Net::FTPPermError when the response code is 550" do
    @server.should_receive(:rmd).and_respond("550 Requested action not taken.")
    -> { @ftp.rmdir("test.folder") }.should raise_error(Net::FTPPermError)
  end
end
