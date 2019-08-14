require_relative '../../spec_helper'
require_relative 'shared/bol'
require 'strscan'

describe "StringScanner#bol?" do
  it_behaves_like :strscan_bol, :bol?
end
