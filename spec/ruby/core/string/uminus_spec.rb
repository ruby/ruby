require_relative '../../spec_helper'

describe 'String#-@' do
  it 'returns self if the String is frozen' do
    input  = 'foo'.freeze
    output = -input

    output.should equal(input)
    output.should.frozen?
  end

  it 'returns a frozen copy if the String is not frozen' do
    input  = 'foo'
    output = -input

    output.should.frozen?
    output.should_not equal(input)
    output.should == 'foo'
  end

  it "returns the same object for equal unfrozen strings" do
    origin = "this is a string"
    dynamic = %w(this is a string).join(' ')

    origin.should_not equal(dynamic)
    (-origin).should equal(-dynamic)
  end

  it "returns the same object when it's called on the same String literal" do
    (-"unfrozen string").should equal(-"unfrozen string")
    (-"unfrozen string").should_not equal(-"another unfrozen string")
  end

  it "deduplicates frozen strings" do
    dynamic = %w(this string is frozen).join(' ').freeze

    dynamic.should_not equal("this string is frozen".freeze)

    (-dynamic).should equal("this string is frozen".freeze)
    (-dynamic).should equal(-"this string is frozen".freeze)
  end

  ruby_version_is "3.0" do
    it "interns the provided string if it is frozen" do
      dynamic = "this string is unique and frozen #{rand}".freeze
      (-dynamic).should equal(dynamic)
    end
  end
end
