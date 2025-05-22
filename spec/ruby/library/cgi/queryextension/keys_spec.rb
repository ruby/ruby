require_relative '../../../spec_helper'

ruby_version_is ""..."3.5" do
  require 'cgi'

  describe "CGI::QueryExtension#keys" do
    before :each do
      ENV['REQUEST_METHOD'], @old_request_method = "GET", ENV['REQUEST_METHOD']
      ENV['QUERY_STRING'], @old_query_string = "one=a&two=b", ENV['QUERY_STRING']

      @cgi = CGI.new
    end

    after :each do
      ENV['REQUEST_METHOD'] = @old_request_method
      ENV['QUERY_STRING']   = @old_query_string
    end

    it "returns all parameter keys as an Array" do
      @cgi.keys.sort.should == ["one", "two"]
    end
  end
end
