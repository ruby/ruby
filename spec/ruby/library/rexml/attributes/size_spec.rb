require_relative '../../../spec_helper'

ruby_version_is ''...'2.8' do
  require_relative 'shared/length'
  require 'rexml/document'

  describe "REXML::Attributes#size" do
    it_behaves_like :rexml_attribute_length, :size
  end
end
