require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative 'shared/index'

ruby_version_is ''...'2.8' do
  describe "Hash#index" do
    it_behaves_like :hash_index, :index
  end
end
