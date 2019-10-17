require_relative '../../../spec_helper'
require_relative '../shared/join'
require 'uri'

describe "URI::Parser#join" do
  it_behaves_like :uri_join, :join, URI::Parser.new
end
