require_relative '../../spec_helper'
require_relative 'shared/pos'
require 'strscan'

describe "StringScanner#pointer" do
  it_behaves_like :strscan_pos, :pointer
end

describe "StringScanner#pointer=" do
  it_behaves_like :strscan_pos_set, :pointer=
end
