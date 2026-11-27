require_relative '../../spec_helper'

describe "NilClass#singleton_method" do
  it "raises regardless of whether NilClass defines the method" do
    -> { nil.singleton_method(:foo) }.should.raise(NameError)
    begin
      def (nil).foo; end
      -> { nil.singleton_method(:foo) }.should.raise(NameError)
    ensure
      NilClass.send(:remove_method, :foo)
    end
  end
end
