require_relative '../../spec_helper'
require_relative 'shared/collect'

describe "Set#map!" do
  it_behaves_like :set_collect_bang, :map!

  ruby_version_is "4.0" do
    it "retains compare_by_identity flag" do
      @set.compare_by_identity
      @set.map! { |x| x * 2 }
      @set.compare_by_identity?.should == true
    end
  end
end
