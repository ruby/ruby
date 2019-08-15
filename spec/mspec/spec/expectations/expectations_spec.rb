require 'spec_helper'
require 'mspec/expectations/expectations'

describe SpecExpectationNotMetError do
  it "is a subclass of StandardError" do
    SpecExpectationNotMetError.ancestors.should include(StandardError)
  end
end

describe SpecExpectationNotFoundError do
  it "is a subclass of StandardError" do
    SpecExpectationNotFoundError.ancestors.should include(StandardError)
  end
end

describe SpecExpectationNotFoundError, "#message" do
  it "returns 'No behavior expectation was found in the example'" do
    m = SpecExpectationNotFoundError.new.message
    m.should == "No behavior expectation was found in the example"
  end
end

describe SpecExpectation, "#fail_with" do
  it "raises an SpecExpectationNotMetError" do
    lambda {
      SpecExpectation.fail_with "expected this", "to equal that"
    }.should raise_error(SpecExpectationNotMetError, "expected this to equal that")
  end
end
