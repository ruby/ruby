require_relative '../../spec_helper'
require_relative 'shared/eql'

describe "String#==" do
  it_behaves_like :string_eql_value, :==

  it "returns false if obj does not respond to to_str" do
    ('hello' == 5).should == false
    not_supported_on :opal do
      ('hello' == :hello).should == false
    end
    ('hello' == mock('x')).should == false
  end

  it "returns obj == self if obj responds to to_str" do
    obj = Object.new

    # String#== merely checks if #to_str is defined. It does
    # not call it.
    obj.stub!(:to_str)

    obj.should_receive(:==).and_return(true)

    ('hello' == obj).should == true
  end

  it "is not fooled by NUL characters" do
    ("abc\0def" == "abc\0xyz").should == false
  end
end
