require_relative '../../spec_helper'

ruby_version_is ""..."3.1" do
  require 'net/ftp'

  describe "Net::FTPPermError" do
    it "is an Exception" do
      Net::FTPPermError.should < Exception
    end

    it "is a subclass of Net::FTPError" do
      Net::FTPPermError.should < Net::FTPError
    end
  end
end
