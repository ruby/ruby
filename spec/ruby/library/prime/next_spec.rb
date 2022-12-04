require_relative '../../spec_helper'

ruby_version_is ""..."3.1" do
  require_relative 'shared/next'
  require 'prime'

  describe "Prime#next" do
    it_behaves_like :prime_next, :next
  end
end
