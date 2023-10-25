require_relative '../../spec_helper'

platform_is_not :windows do
  describe "Process.maxgroups" do
    it "returns the maximum number of gids allowed in the supplemental group access list" do
      Process.maxgroups.should be_kind_of(Integer)
    end

    it "sets the maximum number of gids allowed in the supplemental group access list" do
      n = Process.maxgroups
      begin
        Process.maxgroups = n - 1
        Process.maxgroups.should == n - 1
      ensure
        Process.maxgroups = n
      end
    end
  end
end
