require_relative '../../spec_helper'
require 'timeout'

describe "Timeout::Error" do
  it "is a subclass of RuntimeError" do
    Timeout::Error.ancestors.should.include?(RuntimeError)
  end
end
