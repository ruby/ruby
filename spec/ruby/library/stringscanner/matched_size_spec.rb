require_relative '../../spec_helper'
require_relative 'shared/matched_size'
require 'strscan'

describe "StringScanner#matched_size" do
  it_behaves_like :strscan_matched_size, :matched_size
end
