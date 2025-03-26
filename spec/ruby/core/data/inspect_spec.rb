require_relative '../../spec_helper'
require_relative 'shared/inspect'

ruby_version_is "3.2" do
  describe "Data#inspect" do
    it_behaves_like :data_inspect, :inspect
  end
end
