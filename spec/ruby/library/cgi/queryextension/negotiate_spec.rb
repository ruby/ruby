require_relative '../../../spec_helper'

ruby_version_is ""..."3.5" do
  require 'cgi'

  describe "CGI::QueryExtension#negotiate" do
    before :each do
      ENV['REQUEST_METHOD'], @old_request_method = "GET", ENV['REQUEST_METHOD']
      @cgi = CGI.new
    end

    after :each do
      ENV['REQUEST_METHOD'] = @old_request_method
    end

    it "returns ENV['HTTP_NEGOTIATE']" do
      old_value, ENV['HTTP_NEGOTIATE'] = ENV['HTTP_NEGOTIATE'], "trans"
      begin
        @cgi.negotiate.should == "trans"
      ensure
        ENV['HTTP_NEGOTIATE'] = old_value
      end
    end
  end
end
