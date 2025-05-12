require_relative '../../../spec_helper'

ruby_version_is ""..."3.5" do
  require 'cgi'

  describe "CGI::QueryExtension#remote_ident" do
    before :each do
      ENV['REQUEST_METHOD'], @old_request_method = "GET", ENV['REQUEST_METHOD']
      @cgi = CGI.new
    end

    after :each do
      ENV['REQUEST_METHOD'] = @old_request_method
    end

    it "returns ENV['REMOTE_IDENT']" do
      old_value, ENV['REMOTE_IDENT'] = ENV['REMOTE_IDENT'], "no-idea-what-this-is-for"
      begin
        @cgi.remote_ident.should == "no-idea-what-this-is-for"
      ensure
        ENV['REMOTE_IDENT'] = old_value
      end
    end
  end
end
