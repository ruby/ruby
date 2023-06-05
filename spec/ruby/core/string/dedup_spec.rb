require_relative '../../spec_helper'
require_relative 'shared/dedup'

describe 'String#dedup' do
  ruby_version_is '3.2' do
    it_behaves_like :string_dedup, :dedup
  end
end
