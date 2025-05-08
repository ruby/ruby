require_relative '../../../spec_helper'

ruby_version_is ""..."3.5" do
  require 'cgi'

  describe "CGI::QueryExtension#path_translated" do
    before :each do
      ENV['REQUEST_METHOD'], @old_request_method = "GET", ENV['REQUEST_METHOD']
      @cgi = CGI.new
    end

    after :each do
      ENV['REQUEST_METHOD'] = @old_request_method
    end

    it "returns ENV['PATH_TRANSLATED']" do
      old_value, ENV['PATH_TRANSLATED'] = ENV['PATH_TRANSLATED'], "/full/path/to/dir"
      begin
        @cgi.path_translated.should == "/full/path/to/dir"
      ensure
        ENV['PATH_TRANSLATED'] = old_value
      end
    end
  end
end
