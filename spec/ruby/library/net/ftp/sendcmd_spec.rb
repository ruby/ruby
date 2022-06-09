require_relative '../../../spec_helper'

ruby_version_is ""..."3.1" do
  require_relative 'spec_helper'
  require_relative 'fixtures/server'

  describe "Net::FTP#sendcmd" do
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

    it "sends the passed command to the server" do
      @ftp.sendcmd("HELP")
      @ftp.last_response.should == "211 System status, or system help reply. (HELP)\n"
    end

    it "returns the server's response" do
      @ftp.sendcmd("HELP").should == "211 System status, or system help reply. (HELP)\n"
    end

    it "raises no error when the response code is 1xx, 2xx or 3xx" do
      @server.should_receive(:help).and_respond("120 Service ready in nnn minutes.")
      -> { @ftp.sendcmd("HELP") }.should_not raise_error

      @server.should_receive(:help).and_respond("200 Command okay.")
      -> { @ftp.sendcmd("HELP") }.should_not raise_error

      @server.should_receive(:help).and_respond("350 Requested file action pending further information.")
      -> { @ftp.sendcmd("HELP") }.should_not raise_error
    end

    it "raises a Net::FTPTempError when the response code is 4xx" do
      @server.should_receive(:help).and_respond("421 Service not available, closing control connection.")
      -> { @ftp.sendcmd("HELP") }.should raise_error(Net::FTPTempError)
    end

    it "raises a Net::FTPPermError when the response code is 5xx" do
      @server.should_receive(:help).and_respond("500 Syntax error, command unrecognized.")
      -> { @ftp.sendcmd("HELP") }.should raise_error(Net::FTPPermError)
    end

    it "raises a Net::FTPProtoError when the response code is not between 1xx-5xx" do
      @server.should_receive(:help).and_respond("999 Invalid response.")
      -> { @ftp.sendcmd("HELP") }.should raise_error(Net::FTPProtoError)
    end
  end
end
