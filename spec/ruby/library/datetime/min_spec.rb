require_relative '../../spec_helper'
require_relative 'shared/min'

describe "DateTime.min" do
  it_behaves_like :datetime_min, :min
end
