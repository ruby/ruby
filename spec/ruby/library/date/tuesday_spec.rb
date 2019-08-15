require_relative '../../spec_helper'
require 'date'

describe "Date#tuesday?" do
  it "should be tuesday" do
    Date.new(2000, 1, 4).tuesday?.should be_true
  end
end
