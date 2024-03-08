require_relative '../../../spec_helper'
require 'net/http'
require_relative 'fixtures/http_server'
require_relative 'shared/request_head'

describe "Net::HTTP#request_head" do
  it_behaves_like :net_http_request_head, :request_head
end
