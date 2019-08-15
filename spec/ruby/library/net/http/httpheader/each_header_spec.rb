require_relative '../../../../spec_helper'
require 'net/http'
require_relative 'fixtures/classes'
require_relative 'shared/each_header'

describe "Net::HTTPHeader#each_header" do
  it_behaves_like :net_httpheader_each_header, :each_header
end
