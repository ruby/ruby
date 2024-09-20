require_relative '../../spec_helper'
require 'net/ftp'

describe "Net::FTPReplyError" do
  it "is an Exception" do
    Net::FTPReplyError.should < Exception
  end

  it "is a subclass of Net::FTPError" do
    Net::FTPPermError.should < Net::FTPError
  end
end
