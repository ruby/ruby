require_relative '../../../spec_helper'
require_relative '../shared/extract'
require 'uri'

describe "URI::Parser#extract" do
  it_behaves_like :uri_extract, :extract, URI::Parser.new
end
