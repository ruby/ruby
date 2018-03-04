require_relative '../../spec_helper'
require 'net/ftp'

describe "Net::FTPProtoError" do
  it "is an Exception" do
    Net::FTPProtoError.should < Exception
  end

  it "is a subclass of Net::FTPError" do
    Net::FTPPermError.should < Net::FTPError
  end
end
