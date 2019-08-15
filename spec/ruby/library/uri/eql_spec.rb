require_relative '../../spec_helper'
require_relative 'fixtures/normalization'
require_relative 'shared/eql'
require 'uri'

describe "URI#eql?" do
  it_behaves_like :uri_eql, :eql?

  it_behaves_like :uri_eql_against_other_types, :eql?
end
