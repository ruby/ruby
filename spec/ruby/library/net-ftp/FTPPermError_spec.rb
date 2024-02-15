require_relative '../../spec_helper'
require 'net/ftp'

describe "Net::FTPPermError" do
  it "is an Exception" do
    Net::FTPPermError.should < Exception
  end

  it "is a subclass of Net::FTPError" do
    Net::FTPPermError.should < Net::FTPError
  end
end
