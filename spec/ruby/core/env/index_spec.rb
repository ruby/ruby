require_relative '../../spec_helper'
require_relative 'shared/key'

ruby_version_is ''...'2.8' do
  describe "ENV.index" do
    it_behaves_like :env_key, :index

    it "warns about deprecation" do
      -> do
        ENV.index("foo")
      end.should complain(/warning: ENV.index is deprecated; use ENV.key/)
    end
  end
end
