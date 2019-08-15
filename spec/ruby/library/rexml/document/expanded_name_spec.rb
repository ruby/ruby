require 'rexml/document'
require_relative '../../../spec_helper'

describe :document_expanded_name, shared: true do
  it "returns an empty string for root" do # root nodes have no expanded name
    REXML::Document.new.send(@method).should == ""
  end
end

describe "REXML::Document#expanded_name" do
  it_behaves_like :document_expanded_name, :expanded_name
end

describe "REXML::Document#name" do
  it_behaves_like :document_expanded_name, :name
end
