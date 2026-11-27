require_relative '../../spec_helper'

ruby_version_is ""..."4.1" do
  require_relative 'spec_helper'

  describe "Net::FTP#binary" do
    it "returns true when self is in binary mode" do
      ftp = Net::FTP.new
      ftp.binary.should == true

      ftp.binary = false
      ftp.binary.should == false
    end
  end

  describe "Net::FTP#binary=" do
    it "sets self to binary mode when passed true" do
      ftp = Net::FTP.new

      ftp.binary = true
      ftp.binary.should == true

      ftp.binary = false
      ftp.binary.should == false
    end
  end
end
