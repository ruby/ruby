require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative 'shared/concat'

describe "String#+" do
  it_behaves_like :string_concat_encoding, :+
  it_behaves_like :string_concat_type_coercion, :+

  it "returns a new string containing the given string concatenated to self" do
    ("" + "").should == ""
    ("" + "Hello").should == "Hello"
    ("Hello" + "").should == "Hello"
    ("Ruby !" + "= Rubinius").should == "Ruby != Rubinius"
  end

  it "converts any non-String argument with #to_str" do
    c = mock 'str'
    c.should_receive(:to_str).any_number_of_times.and_return(' + 1 = 2')

    ("1" + c).should == '1 + 1 = 2'
  end

  it "raises a TypeError when given any object that fails #to_str" do
    -> { "" + Object.new }.should raise_error(TypeError)
    -> { "" + 65 }.should raise_error(TypeError)
  end

  it "doesn't return subclass instances" do
    (StringSpecs::MyString.new("hello") + "").should be_an_instance_of(String)
    (StringSpecs::MyString.new("hello") + "foo").should be_an_instance_of(String)
    (StringSpecs::MyString.new("hello") + StringSpecs::MyString.new("foo")).should be_an_instance_of(String)
    (StringSpecs::MyString.new("hello") + StringSpecs::MyString.new("")).should be_an_instance_of(String)
    (StringSpecs::MyString.new("") + StringSpecs::MyString.new("")).should be_an_instance_of(String)
    ("hello" + StringSpecs::MyString.new("foo")).should be_an_instance_of(String)
    ("hello" + StringSpecs::MyString.new("")).should be_an_instance_of(String)
  end
end
