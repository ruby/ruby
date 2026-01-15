require_relative '../../spec_helper'
require_relative 'shared/dedup'

describe 'String#dedup' do
  it_behaves_like :string_dedup, :dedup
end
