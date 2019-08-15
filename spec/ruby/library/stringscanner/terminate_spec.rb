require_relative '../../spec_helper'
require_relative 'shared/terminate'
require 'strscan'

describe "StringScanner#terminate" do
    it_behaves_like :strscan_terminate, :terminate
end
