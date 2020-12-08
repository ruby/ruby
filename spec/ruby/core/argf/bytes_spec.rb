require_relative '../../spec_helper'
require_relative 'shared/each_byte'

ruby_version_is ''...'3.0' do
  describe "ARGF.bytes" do
    it_behaves_like :argf_each_byte, :bytes
  end
end
