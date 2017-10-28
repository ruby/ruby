require File.expand_path('../../../spec_helper', __FILE__)
require 'date'

describe "Date#tuesday?" do
  it "should be tuesday" do
    Date.new(2000, 1, 4).tuesday?.should be_true
  end
end
