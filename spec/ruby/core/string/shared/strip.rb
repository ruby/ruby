require_relative '../../../spec_helper'
require_relative '../fixtures/classes'

describe :string_strip, shared: true do
  ruby_version_is '3.0' do
    it "returns String instances when called on a subclass" do
      StringSpecs::MyString.new(" hello ").send(@method).should be_an_instance_of(String)
      StringSpecs::MyString.new(" ").send(@method).should be_an_instance_of(String)
      StringSpecs::MyString.new("").send(@method).should be_an_instance_of(String)
    end
  end

  ruby_version_is ''...'3.0' do
    it "returns subclass instances when called on a subclass" do
      StringSpecs::MyString.new(" hello ").send(@method).should be_an_instance_of(StringSpecs::MyString)
      StringSpecs::MyString.new(" ").send(@method).should be_an_instance_of(StringSpecs::MyString)
      StringSpecs::MyString.new("").send(@method).should be_an_instance_of(StringSpecs::MyString)
    end
  end
end
