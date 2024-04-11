require_relative '../../../spec_helper'
require 'net/http'
require_relative 'fixtures/http_server'
require_relative 'shared/request_get'

describe "Net::HTTP#get2" do
  it_behaves_like :net_http_request_get, :get2
end
