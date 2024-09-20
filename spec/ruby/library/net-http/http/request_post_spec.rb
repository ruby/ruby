require_relative '../../../spec_helper'
require 'net/http'
require_relative 'fixtures/http_server'
require_relative 'shared/request_post'

describe "Net::HTTP#request_post" do
  it_behaves_like :net_http_request_post, :request_post
end
