require_relative '../../spec_helper'
require_relative 'shared/get_byte'
require 'strscan'

describe "StringScanner#get_byte" do
  it_behaves_like :strscan_get_byte, :get_byte
end
