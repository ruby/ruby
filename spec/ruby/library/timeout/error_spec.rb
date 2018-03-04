require_relative '../../spec_helper'
require 'timeout'

describe "Timeout::Error" do
  it "is a subclass of RuntimeError" do
    RuntimeError.should be_ancestor_of(Timeout::Error)
  end
end
