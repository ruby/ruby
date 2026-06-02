require_relative '../../spec_helper'

ruby_version_is ""..."4.1" do
  require_relative 'spec_helper'

  describe "Net::FTP#debug_mode" do
    it "returns true when self is in debug mode" do
      ftp = Net::FTP.new
      ftp.debug_mode.should == false

      ftp.debug_mode = true
      ftp.debug_mode.should == true
    end
  end

  describe "Net::FTP#debug_mode=" do
    it "sets self into debug mode when passed true" do
      ftp = Net::FTP.new
      ftp.debug_mode = true
      ftp.debug_mode.should == true

      ftp.debug_mode = false
      ftp.debug_mode.should == false
    end
  end
end
