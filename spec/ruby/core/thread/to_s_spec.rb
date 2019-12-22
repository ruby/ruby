require_relative '../../spec_helper'
require_relative 'shared/to_s'

ruby_version_is "2.5" do
  describe "Thread#to_s" do
    it_behaves_like :thread_to_s, :to_s
  end
end
