require_relative '../../spec_helper'

describe "NilClass#singleton_method" do
  ruby_version_is '3.3' do
    it "raises regardless of whether NilClass defines the method" do
      -> { nil.singleton_method(:foo) }.should raise_error(NameError)
      begin
        def (nil).foo; end
        -> { nil.singleton_method(:foo) }.should raise_error(NameError)
      ensure
        NilClass.send(:remove_method, :foo)
      end
    end
  end
end
