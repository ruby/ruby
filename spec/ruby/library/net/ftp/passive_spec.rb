require_relative '../../../spec_helper'
require_relative 'spec_helper'

describe "Net::FTP#passive" do
  it "returns true when self is in passive mode" do
    ftp = Net::FTP.new
    ftp.passive.should be_false

    ftp.passive = true
    ftp.passive.should be_true
  end

  it "returns :PASV when self is in passive mode :PASV" do
    ftp = Net::FTP.new(nil, passive: :PASV)
    ftp.passive.should equal(:PASV)
  end

  it "returns :EPSV when self is in passive mode :EPSV" do
    ftp = Net::FTP.new(nil, passive: :EPSV)
    ftp.passive.should equal(:EPSV)
  end

  it "is the value of Net::FTP.default_value by default" do
    ruby_exe(fixture(__FILE__, "passive.rb")).should == "true"
  end
end

describe "Net::FTP#passive=" do
  it "sets self to passive mode when passed true" do
    ftp = Net::FTP.new

    ftp.passive = true
    ftp.passive.should be_true

    ftp.passive = false
    ftp.passive.should be_false
  end

  it "sets self to passive mode :PASV when passed :PASV" do
    ftp = Net::FTP.new
    ftp.passive.should be_false

    ftp.passive = :PASV
    ftp.passive.should equal(:PASV)
  end

  it "sets self to passive mode :EPSV when passed :EPSV" do
    ftp = Net::FTP.new
    ftp.passive.should be_false

    ftp.passive = :EPSV
    ftp.passive.should equal(:EPSV)
  end
end
