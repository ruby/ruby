require_relative '../../../spec_helper'

ruby_version_is ''...'3.0' do
  require 'rexml/document'

  describe "REXML::Text.normalize" do
    it "escapes a string with <, >, &, ' and \" " do
      REXML::Text.normalize("< > & \" '").should == "&lt; &gt; &amp; &quot; &apos;"
    end
  end
end
