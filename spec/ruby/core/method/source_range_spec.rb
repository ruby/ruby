require_relative '../../spec_helper'
require_relative 'shared/source_range'

ruby_version_is "4.1" do
  describe "Method#source_range" do
    before :each do
      @object = -> method { method }
    end

    it_behaves_like :method_source_range, :source_range
  end
end
