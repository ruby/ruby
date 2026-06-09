require_relative '../../spec_helper'
require_relative 'shared/then'

describe "Kernel#then" do
  ruby_version_is ""..."3.4" do
    it_behaves_like :kernel_then, :then
  end

  ruby_version_is "3.4" do
    it "is an alias of Kernel#yield_self" do
      Kernel.instance_method(:then).should == Kernel.instance_method(:yield_self)
    end
  end
end
