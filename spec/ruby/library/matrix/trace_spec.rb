require_relative '../../spec_helper'

ruby_version_is ""..."3.1" do
  require_relative 'shared/trace'
  require 'matrix'

  describe "Matrix#trace" do
    it_behaves_like :trace, :trace
  end
end
