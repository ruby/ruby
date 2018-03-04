require_relative '../../spec_helper'
require_relative 'shared/equal_value'

describe "Regexp#==" do
  it_behaves_like :regexp_eql, :==
end
