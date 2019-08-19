require 'rexml/document'
require_relative '../../../spec_helper'

describe "REXML::Document#node_type" do
  it "returns :document" do
    REXML::Document.new.node_type.should == :document
  end
end
