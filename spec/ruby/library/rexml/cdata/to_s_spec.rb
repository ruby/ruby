require_relative '../../../spec_helper'

ruby_version_is ''...'3.0' do
  require_relative 'shared/to_s'
  require 'rexml/document'

  describe "REXML::CData#to_s" do
    it_behaves_like :rexml_cdata_to_s, :to_s
  end
end
