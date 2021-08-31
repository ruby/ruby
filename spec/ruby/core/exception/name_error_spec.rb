require_relative '../../spec_helper'

describe "NameError.new" do
  it "should take optional name argument" do
    NameError.new("msg","name").name.should == "name"
  end

  it "accepts a :receiver keyword argument" do
    receiver = mock("receiver")

    error = NameError.new("msg", :name, receiver: receiver)

    error.receiver.should == receiver
    error.name.should == :name
  end
end

describe "NameError#dup" do
  it "copies the name and receiver" do
    begin
      foo
    rescue NameError => ne
      name_error_dup = ne.dup
      name_error_dup.name.should == :foo
      name_error_dup.receiver.should == self
    end
  end
end
