require_relative '../../spec_helper'

ruby_version_is ""..."4.1" do
  require_relative 'spec_helper'

  describe "Net::FTP#resume" do
    it "returns true when self is set to resume uploads/downloads" do
      ftp = Net::FTP.new
      ftp.resume.should == false

      ftp.resume = true
      ftp.resume.should == true
    end
  end

  describe "Net::FTP#resume=" do
    it "sets self to resume uploads/downloads when set to true" do
      ftp = Net::FTP.new
      ftp.resume = true
      ftp.resume.should == true

      ftp.resume = false
      ftp.resume.should == false
    end
  end
end
