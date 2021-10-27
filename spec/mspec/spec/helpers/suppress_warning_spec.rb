require 'spec_helper'
require 'mspec/guards'
require 'mspec/helpers'

RSpec.describe Object, "#suppress_warning" do
  it "hides warnings" do
    suppress_warning do
      warn "should not be shown"
    end
  end

  it "yields the block" do
    a = 0
    suppress_warning do
      a = 1
    end
    expect(a).to eq(1)
  end
end
