require_relative '../../spec_helper'
require_relative 'shared/bol'
require 'strscan'

describe "StringScanner#beginning_of_line?" do
  it_behaves_like :strscan_bol, :beginning_of_line?
end
