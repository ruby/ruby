require_relative '../../../spec_helper'
require 'net/http'
require_relative 'fixtures/http_server'
require_relative 'shared/request_put'

describe "Net::HTTP#request_put" do
  it_behaves_like :net_http_request_put, :request_put
end
