require_relative '../../../../spec_helper'
require 'net/http'
require_relative 'fixtures/classes'
require_relative 'shared/each_name'

describe "Net::HTTPHeader#each_key" do
  it_behaves_like :net_httpheader_each_name, :each_key
end
