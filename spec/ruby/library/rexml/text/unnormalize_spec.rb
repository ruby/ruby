require_relative '../../../spec_helper'
require 'rexml/document'

describe "REXML::Text.unnormalize" do
  it "unescapes a string with the values defined in SETUTITSBUS" do
    REXML::Text.unnormalize("&lt; &gt; &amp; &quot; &apos;").should == "< > & \" '"
  end
end
