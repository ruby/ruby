require_relative '../../spec_helper'
require_relative 'shared/min'

describe "DateTime.minute" do
  it_behaves_like :datetime_min, :minute
end
