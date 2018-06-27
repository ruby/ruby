require_relative '../../spec_helper'
require 'rbconfig'

describe 'RbConfig::CONFIG values' do
  it 'are all strings' do
    RbConfig::CONFIG.each do |k, v|
      k.should be_kind_of String
      v.should be_kind_of String
    end
  end
end
