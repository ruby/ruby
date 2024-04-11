require_relative '../../spec_helper'
require_relative 'spec_helper'
require_relative 'fixtures/server'

describe "Net::FTP#chdir" do
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

  describe "when switching to the parent directory" do
    it "sends the 'CDUP' command to the server" do
      @ftp.chdir("..")
      @ftp.last_response.should == "200 Command okay. (CDUP)\n"
    end

    it "returns nil" do
      @ftp.chdir("..").should be_nil
    end

    it "does not raise a Net::FTPPermError when the response code is 500" do
      @server.should_receive(:cdup).and_respond("500 Syntax error, command unrecognized.")
      -> { @ftp.chdir("..") }.should_not raise_error(Net::FTPPermError)
    end

    it "raises a Net::FTPPermError when the response code is 501" do
      @server.should_receive(:cdup).and_respond("501 Syntax error in parameters or arguments.")
      -> { @ftp.chdir("..") }.should raise_error(Net::FTPPermError)
    end

    it "raises a Net::FTPPermError when the response code is 502" do
      @server.should_receive(:cdup).and_respond("502 Command not implemented.")
      -> { @ftp.chdir("..") }.should raise_error(Net::FTPPermError)
    end

    it "raises a Net::FTPTempError when the response code is 421" do
      @server.should_receive(:cdup).and_respond("421 Service not available, closing control connection.")
      -> { @ftp.chdir("..") }.should raise_error(Net::FTPTempError)
    end

    it "raises a Net::FTPPermError when the response code is 530" do
      @server.should_receive(:cdup).and_respond("530 Not logged in.")
      -> { @ftp.chdir("..") }.should raise_error(Net::FTPPermError)
    end

    it "raises a Net::FTPPermError when the response code is 550" do
      @server.should_receive(:cdup).and_respond("550 Requested action not taken.")
      -> { @ftp.chdir("..") }.should raise_error(Net::FTPPermError)
    end
  end

  it "writes the 'CWD' command with the passed directory to the socket" do
    @ftp.chdir("test")
    @ftp.last_response.should == "200 Command okay. (CWD test)\n"
  end

  it "returns nil" do
    @ftp.chdir("test").should be_nil
  end

  it "raises a Net::FTPPermError when the response code is 500" do
    @server.should_receive(:cwd).and_respond("500 Syntax error, command unrecognized.")
    -> { @ftp.chdir("test") }.should raise_error(Net::FTPPermError)
  end

  it "raises a Net::FTPPermError when the response code is 501" do
    @server.should_receive(:cwd).and_respond("501 Syntax error in parameters or arguments.")
    -> { @ftp.chdir("test") }.should raise_error(Net::FTPPermError)
  end

  it "raises a Net::FTPPermError when the response code is 502" do
    @server.should_receive(:cwd).and_respond("502 Command not implemented.")
    -> { @ftp.chdir("test") }.should raise_error(Net::FTPPermError)
  end

  it "raises a Net::FTPTempError when the response code is 421" do
    @server.should_receive(:cwd).and_respond("421 Service not available, closing control connection.")
    -> { @ftp.chdir("test") }.should raise_error(Net::FTPTempError)
  end

  it "raises a Net::FTPPermError when the response code is 530" do
    @server.should_receive(:cwd).and_respond("530 Not logged in.")
    -> { @ftp.chdir("test") }.should raise_error(Net::FTPPermError)
  end

  it "raises a Net::FTPPermError when the response code is 550" do
    @server.should_receive(:cwd).and_respond("550 Requested action not taken.")
    -> { @ftp.chdir("test") }.should raise_error(Net::FTPPermError)
  end
end
