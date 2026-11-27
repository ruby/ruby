require_relative '../../spec_helper'

describe "Time#xmlschema" do
  ruby_version_is "3.4" do
    it "is an alias of Time#iso8601" do
      Time.instance_method(:xmlschema).should == Time.instance_method(:iso8601)
    end
  end
end
