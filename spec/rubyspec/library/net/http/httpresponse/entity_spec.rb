require File.expand_path('../../../../../spec_helper', __FILE__)
require 'net/http'
require File.expand_path('../shared/body', __FILE__)

describe "Net::HTTPResponse#entity" do
  it_behaves_like :net_httpresponse_body, :entity
end
