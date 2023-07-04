require_relative '../../spec_helper'

ruby_version_is ""..."3.3" do
  require 'getoptlong'
  require_relative 'shared/each'

  describe "GetoptLong#each_option" do
    it_behaves_like :getoptlong_each, :each_option
  end
end
