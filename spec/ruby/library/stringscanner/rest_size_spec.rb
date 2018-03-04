require_relative '../../spec_helper'
require_relative 'shared/rest_size'
require 'strscan'

describe "StringScanner#rest_size" do
  it_behaves_like :strscan_rest_size, :rest_size
end
