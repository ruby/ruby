require_relative '../../spec_helper'
require_relative 'shared/update'

ruby_version_is "2.7" do
  describe "ENV.merge!" do
    it_behaves_like :env_update, :merge!
  end
end
