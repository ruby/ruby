require_relative '../../../spec_helper'

ruby_version_is ''...'3.0' do
  require 'rexml/document'

  describe "REXML::Text#empty?" do
    it "returns true if the text is empty" do
      REXML::Text.new("").should.empty?
    end

    it "returns false if the text is not empty" do
      REXML::Text.new("some_text").should_not.empty?
    end
  end
end
