require_relative '../../../../spec_helper'
require 'net/http'
require_relative 'fixtures/classes'
require_relative 'shared/each_capitalized'

describe "Net::HTTPHeader#canonical_each" do
  it_behaves_like :net_httpheader_each_capitalized, :canonical_each
end
