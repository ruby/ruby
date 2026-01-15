require 'spec_helper'
require 'mspec/expectations/expectations'

RSpec.describe SpecExpectationNotMetError do
  it "is a subclass of StandardError" do
    expect(SpecExpectationNotMetError.ancestors).to include(StandardError)
  end
end

RSpec.describe SpecExpectationNotFoundError do
  it "is a subclass of StandardError" do
    expect(SpecExpectationNotFoundError.ancestors).to include(StandardError)
  end
end

RSpec.describe SpecExpectationNotFoundError, "#message" do
  it "returns 'No behavior expectation was found in the example'" do
    m = SpecExpectationNotFoundError.new.message
    expect(m).to eq("No behavior expectation was found in the example")
  end
end

RSpec.describe SpecExpectation, "#fail_with" do
  it "raises an SpecExpectationNotMetError" do
    expect {
      SpecExpectation.fail_with "expected this", "to equal that"
    }.to raise_error(SpecExpectationNotMetError, "expected this to equal that")
  end
end
