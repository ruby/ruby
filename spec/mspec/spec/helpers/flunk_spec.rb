require 'spec_helper'
require 'mspec/expectations/expectations'
require 'mspec/runner/mspec'
require 'mspec/guards'
require 'mspec/helpers'

RSpec.describe Object, "#flunk" do
  before :each do
    allow(MSpec).to receive(:actions)
    allow(MSpec).to receive(:current).and_return(double("spec state").as_null_object)
  end

  it "raises an SpecExpectationNotMetError unconditionally" do
    expect { flunk }.to raise_error(SpecExpectationNotMetError)
  end

  it "accepts on argument for an optional message" do
    expect {flunk "test"}.to raise_error(SpecExpectationNotMetError)
  end
end
