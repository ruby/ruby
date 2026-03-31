require_relative '../../spec_helper'

describe "TrueClass#singleton_method" do
  it "raises regardless of whether TrueClass defines the method" do
    -> { true.singleton_method(:foo) }.should raise_error(NameError)
    begin
      def (true).foo; end
      -> { true.singleton_method(:foo) }.should raise_error(NameError)
    ensure
      TrueClass.send(:remove_method, :foo)
    end
  end
end
