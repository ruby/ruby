require_relative '../../../spec_helper'
require_relative 'shared/length'
require 'rexml/document'

describe "REXML::Attributes#length" do
 it_behaves_like :rexml_attribute_length, :length
end
