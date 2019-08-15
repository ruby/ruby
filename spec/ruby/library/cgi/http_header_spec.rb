require_relative '../../spec_helper'
require 'cgi'

require_relative 'shared/http_header'

describe "CGI#http_header" do
  it_behaves_like :cgi_http_header, :http_header
end
