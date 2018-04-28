require_relative '../../spec_helper'

describe 'String#-@' do
  it 'returns self if the String is frozen' do
    input  = 'foo'.freeze
    output = -input

    output.equal?(input).should == true
    output.frozen?.should == true
  end

  it 'returns a frozen copy if the String is not frozen' do
    input  = 'foo'
    output = -input

    output.frozen?.should == true
    output.should == 'foo'
  end

  ruby_version_is "2.5" do
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

    it "is an identity function if the string is frozen" do
      dynamic = %w(this string is frozen).join(' ').freeze

      (-dynamic).should equal(dynamic)

      dynamic.should_not equal("this string is frozen".freeze)
      (-dynamic).should_not equal("this string is frozen".freeze)
      (-dynamic).should_not equal(-"this string is frozen".freeze)
    end
  end
end
