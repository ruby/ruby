require_relative '../../../spec_helper'
require_relative 'spec_helper'

describe "Net::FTP#return_code" do
  before :each do
    @ftp = Net::FTP.new
  end

  it "outputs a warning and returns a newline" do
    -> do
      @ftp.return_code.should == "\n"
    end.should complain(/warning: Net::FTP#return_code is obsolete and do nothing/)
  end
end

describe "Net::FTP#return_code=" do
  before :each do
    @ftp = Net::FTP.new
  end

  it "outputs a warning" do
    -> { @ftp.return_code = 123 }.should complain(/warning: Net::FTP#return_code= is obsolete and do nothing/)
  end
end
