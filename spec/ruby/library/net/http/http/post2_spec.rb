require_relative '../../../../spec_helper'
require 'net/http'
require_relative 'fixtures/http_server'
require_relative 'shared/request_post'

describe "Net::HTTP#post2" do
  it_behaves_like :net_ftp_request_post, :post2
end
