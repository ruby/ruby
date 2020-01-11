require_relative '../../../spec_helper'

ruby_version_is ''...'2.8' do
  require_relative 'shared/add'
  require 'rexml/document'

  describe "REXML::Attributes#<<" do
    it_behaves_like :rexml_attribute_add, :<<
  end
end
