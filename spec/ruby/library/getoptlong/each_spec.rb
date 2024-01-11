require_relative '../../spec_helper'

ruby_version_is ""..."3.4" do
  require 'getoptlong'
  require_relative 'shared/each'

  describe "GetoptLong#each" do
    it_behaves_like :getoptlong_each, :each
  end
end
