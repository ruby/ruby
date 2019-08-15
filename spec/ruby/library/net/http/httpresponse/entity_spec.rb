require_relative '../../../../spec_helper'
require 'net/http'
require_relative 'shared/body'

describe "Net::HTTPResponse#entity" do
  it_behaves_like :net_httpresponse_body, :entity
end
