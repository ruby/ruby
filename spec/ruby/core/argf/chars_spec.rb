require_relative '../../spec_helper'
require_relative 'shared/each_char'

ruby_version_is ''...'2.8' do
  describe "ARGF.chars" do
    it_behaves_like :argf_each_char, :chars
  end
end
