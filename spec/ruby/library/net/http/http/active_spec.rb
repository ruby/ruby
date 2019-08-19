require_relative '../../../../spec_helper'
require 'net/http'
require_relative 'fixtures/http_server'
require_relative 'shared/started'

describe "Net::HTTP#active?" do
  it_behaves_like :net_http_started_p, :active?
end
