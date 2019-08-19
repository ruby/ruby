require_relative '../../spec_helper'

ruby_version_is "2.6" do
  describe "NilClass#=~" do
    it "returns nil matching any object" do
      o = Object.new

      suppress_warning do
        (o =~ /Object/).should   be_nil
        (o =~ 'Object').should   be_nil
        (o =~ Object).should     be_nil
        (o =~ Object.new).should be_nil
        (o =~ nil).should        be_nil
        (o =~ false).should      be_nil
        (o =~ true).should       be_nil
      end
    end
  end
end
