require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative 'shared/replace'

describe "String#initialize" do
  it "is a private method" do
    String.should have_private_instance_method(:initialize)
  end

  describe "with no arguments" do
    it "does not change self" do
      s = "some string"
      s.send :initialize
      s.should == "some string"
    end

    it "does not raise an exception when frozen" do
      a = "hello".freeze
      a.send(:initialize).should equal(a)
    end
  end

  describe "with an argument" do
    it_behaves_like :string_replace, :initialize
  end
end
