require_relative '../../../spec_helper'

ruby_version_is ""..."3.5" do
  require 'cgi'

  describe "CGI::QueryExtension#accept_encoding" do
    before :each do
      ENV['REQUEST_METHOD'], @old_request_method = "GET", ENV['REQUEST_METHOD']
      @cgi = CGI.new
    end

    after :each do
      ENV['REQUEST_METHOD'] = @old_request_method
    end

    it "returns ENV['HTTP_ACCEPT_ENCODING']" do
      old_value, ENV['HTTP_ACCEPT_ENCODING'] = ENV['HTTP_ACCEPT_ENCODING'], "gzip,deflate"
      begin
        @cgi.accept_encoding.should == "gzip,deflate"
      ensure
        ENV['HTTP_ACCEPT_ENCODING'] = old_value
      end
    end
  end
end
