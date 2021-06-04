require_relative '../../../spec_helper'

ruby_version_is ''...'3.0' do
  require 'rexml/document'

  describe "REXML::CData#clone" do
    it "makes a copy of itself" do
      c = REXML::CData.new("some text")
      c.clone.to_s.should == c.to_s
      c.clone.should == c
    end
  end
end
