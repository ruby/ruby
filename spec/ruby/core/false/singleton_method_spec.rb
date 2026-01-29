require_relative '../../spec_helper'

describe "FalseClass#singleton_method" do
  it "raises regardless of whether FalseClass defines the method" do
    -> { false.singleton_method(:foo) }.should raise_error(NameError)
    begin
      def (false).foo; end
      -> { false.singleton_method(:foo) }.should raise_error(NameError)
    ensure
      FalseClass.send(:remove_method, :foo)
    end
  end
end
