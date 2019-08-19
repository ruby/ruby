require_relative '../../spec_helper'
require_relative 'shared/eos'
require 'strscan'

describe "StringScanner#eos?" do
  it_behaves_like :strscan_eos, :eos?
end
