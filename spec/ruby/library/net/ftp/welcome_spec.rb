require_relative '../../../spec_helper'
require_relative 'spec_helper'
require_relative 'fixtures/server'

describe "Net::FTP#welcome" do
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

  it "returns the server's welcome message" do
    @ftp.welcome.should be_nil
    @ftp.login
    @ftp.welcome.should == "230 User logged in, proceed. (USER anonymous)\n"
  end
end
