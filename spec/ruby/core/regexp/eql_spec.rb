require_relative '../../spec_helper'
require_relative 'shared/equal_value'

describe "Regexp#eql?" do
  it_behaves_like :regexp_eql, :eql?
end
