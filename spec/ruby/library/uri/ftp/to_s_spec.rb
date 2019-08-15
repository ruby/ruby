require_relative '../../../spec_helper'
require 'uri'


describe "URI::FTP#to_s" do
  before :each do
    @url = URI.parse('ftp://example.com')
  end

  it "escapes the leading /" do
    @url.path = '/foo'

    @url.to_s.should == 'ftp://example.com/%2Ffoo'
  end
end
