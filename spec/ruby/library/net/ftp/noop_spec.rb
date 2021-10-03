require_relative '../../../spec_helper'

ruby_version_is ""..."3.1" do
  require_relative 'spec_helper'
  require_relative 'fixtures/server'

  describe "Net::FTP#noop" do
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

    it "sends the NOOP command to the server" do
      @ftp.noop
      @ftp.last_response.should == "200 Command okay. (NOOP)\n"
    end

    it "returns nil" do
      @ftp.noop.should be_nil
    end

    it "raises a Net::FTPPermError when the response code is 500" do
      @server.should_receive(:noop).and_respond("500 Syntax error, command unrecognized.")
      -> { @ftp.noop }.should raise_error(Net::FTPPermError)
    end

    it "raises a Net::FTPTempError when the response code is 421" do
      @server.should_receive(:noop).and_respond("421 Service not available, closing control connection.")
      -> { @ftp.noop }.should raise_error(Net::FTPTempError)
    end
  end
end
