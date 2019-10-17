require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative 'shared/eql'

describe "Hash#eql?" do
  it_behaves_like :hash_eql, :eql?
  it_behaves_like :hash_eql_additional, :eql?
  it_behaves_like :hash_eql_additional_more, :eql?
end
