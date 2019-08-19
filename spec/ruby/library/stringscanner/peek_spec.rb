require_relative '../../spec_helper'
require_relative 'shared/peek'
require 'strscan'

describe "StringScanner#peek" do
  it_behaves_like :strscan_peek, :peek
end
