require_relative '../../spec_helper'

ruby_version_is ""..."3.1" do
  require 'prime'

  describe "Prime.instance" do
    it "returns a object representing the set of prime numbers" do
      Prime.instance.should be_kind_of(Prime)
    end

    it "returns a object with no obsolete features" do
      Prime.instance.should_not respond_to(:succ)
      Prime.instance.should_not respond_to(:next)
    end

    it "does not complain anything" do
      -> { Prime.instance }.should_not complain
    end

    it "raises a ArgumentError when is called with some arguments" do
      -> { Prime.instance(1) }.should raise_error(ArgumentError)
    end
  end
end
