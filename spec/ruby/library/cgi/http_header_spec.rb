require_relative '../../spec_helper'

ruby_version_is ""..."3.5" do
  require 'cgi'

  require_relative 'shared/http_header'

  describe "CGI#http_header" do
    it_behaves_like :cgi_http_header, :http_header
  end
end
