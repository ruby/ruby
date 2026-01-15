require_relative '../../spec_helper'
require_relative 'shared/concat'
require 'strscan'

describe "StringScanner#<<" do
  it_behaves_like :strscan_concat, :<<
end

describe "StringScanner#<< when passed an Integer" do
  it_behaves_like :strscan_concat_fixnum, :<<
end
