require_relative '../../../spec_helper'
require_relative '../fixtures/classes'
require_relative '../shared/parse'

describe "URI::Parser#parse" do
  it_behaves_like :uri_parse, :parse, URI::Parser.new
end
