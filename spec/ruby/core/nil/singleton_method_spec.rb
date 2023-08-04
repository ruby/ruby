require_relative '../../spec_helper'

describe "NilClass#singleton_method" do
  ruby_version_is '3.3' do
    it "raises regardless of whether NilClass defines the method" do
      proc{nil.singleton_method(:foo)}.should raise_error(NameError)
      begin
        def nil.foo; end
        proc{nil.singleton_method(:foo)}.should raise_error(NameError)
      ensure
        NilClass.send(:remove_method, :foo)
      end
    end
  end
end
