require 'spec_helper'
require 'mspec/expectations/expectations'
require 'mspec/runner/mspec'
require 'mspec/guards'
require 'mspec/helpers'

describe Object, "#flunk" do
  before :each do
    MSpec.stub(:actions)
    MSpec.stub(:current).and_return(double("spec state").as_null_object)
  end

  it "raises an SpecExpectationNotMetError unconditionally" do
    lambda { flunk }.should raise_error(SpecExpectationNotMetError)
  end

  it "accepts on argument for an optional message" do
    lambda {flunk "test"}.should raise_error(SpecExpectationNotMetError)
  end
end
