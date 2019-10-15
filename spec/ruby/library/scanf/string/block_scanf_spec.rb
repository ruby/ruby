require_relative '../../../spec_helper'

ruby_version_is ''...'2.7' do
  require_relative 'shared/block_scanf'
  require 'scanf'

  describe "String#block_scanf" do
    it_behaves_like :scanf_string_block_scanf, :block_scanf
  end
end
