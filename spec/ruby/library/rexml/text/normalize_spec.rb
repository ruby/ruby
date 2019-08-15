require_relative '../../../spec_helper'
require 'rexml/document'

describe "REXML::Text.normalize" do
  it "escapes a string with <, >, &, ' and \" " do
    REXML::Text.normalize("< > & \" '").should == "&lt; &gt; &amp; &quot; &apos;"
  end
end
