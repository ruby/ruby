require_relative '../../spec_helper'
require_relative 'shared/concat'
require 'strscan'

describe "StringScanner#concat" do
  it_behaves_like :strscan_concat, :concat
end

describe "StringScanner#concat when passed a Fixnum" do
  it_behaves_like :strscan_concat_fixnum, :concat
end
