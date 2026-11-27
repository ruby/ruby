require_relative "../../spec_helper"
require_relative 'shared/abs'

describe "Float#magnitude" do
  ruby_version_is ""..."3.4" do
    it_behaves_like :float_abs, :magnitude
  end

  ruby_version_is "3.4" do
    it "is an alias of Float#abs" do
      Float.instance_method(:magnitude).should == Float.instance_method(:abs)
    end
  end
end
