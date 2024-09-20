require_relative '../../../spec_helper'
require 'net/http'
require_relative 'fixtures/classes'
require_relative 'shared/size'

describe "Net::HTTPHeader#length" do
  it_behaves_like :net_httpheader_size, :length
end
