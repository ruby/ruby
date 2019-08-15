require_relative '../../../../spec_helper'
require 'net/http'
require_relative 'fixtures/classes'
require_relative 'shared/each_capitalized'

describe "Net::HTTPHeader#each_capitalized" do
  it_behaves_like :net_httpheader_each_capitalized, :each_capitalized
end
