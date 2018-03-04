require_relative '../../spec_helper'

describe "ARGF" do
  it "is extended by the Enumerable module" do
    ARGF.should be_kind_of(Enumerable)
  end

  it "is an instance of ARGF.class" do
    ARGF.should be_an_instance_of(ARGF.class)
  end
end
