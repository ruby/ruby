require_relative '../../../spec_helper'
require 'rexml/document'

describe "REXML::Text#inspect" do
  it "inspects the string attribute as a string" do
    REXML::Text.new("a text").inspect.should == "a text".inspect
  end
end
