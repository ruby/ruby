require_relative '../../../spec_helper'
require_relative 'shared/to_s'
require 'rexml/document'

describe "REXML::CData#value" do
  it_behaves_like :rexml_cdata_to_s, :value
end
