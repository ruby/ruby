require_relative '../../spec_helper'
require_relative 'shared/isdst'

describe "Time#dst?" do
  it_behaves_like :time_isdst, :dst?
end
