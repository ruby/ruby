require_relative '../../spec_helper'
require_relative 'shared/value'

describe "ENV.value?" do
  it_behaves_like :env_value, :value?
end
