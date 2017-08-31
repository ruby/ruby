require File.dirname(__FILE__) + '/../../spec_helper'
require 'mspec/runner/mspec'
require 'mspec/runner/filters/regexp'

describe RegexpFilter, "#to_regexp" do
  before :each do
    @filter = RegexpFilter.new nil
  end

  it "converts its arguments to Regexp instances" do
    @filter.to_regexp('a(b|c)', 'b[^ab]', 'cc?').should == [/a(b|c)/, /b[^ab]/, /cc?/]
  end
end
