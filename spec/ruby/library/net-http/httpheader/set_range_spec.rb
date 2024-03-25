require_relative '../../../spec_helper'
require 'net/http'
require_relative 'fixtures/classes'
require_relative 'shared/set_range'

describe "Net::HTTPHeader#set_range" do
  it_behaves_like :net_httpheader_set_range, :set_range
end
