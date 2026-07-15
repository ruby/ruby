require_relative '../../spec_helper'
require_relative '../method/shared/source_range'

ruby_version_is "4.1" do
  describe "UnboundMethod#source_range" do
    before :each do
      @object = -> method { method.unbind }
    end

    it_behaves_like :method_source_range, :source_range
  end
end
