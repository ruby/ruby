require_relative '../../spec_helper'

ruby_version_is ""..."4.1" do
  require 'net/ftp'

  describe "Net::FTPError" do
    it "is an Exception" do
      Net::FTPError.should < Exception
    end
  end
end
