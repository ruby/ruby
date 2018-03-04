require_relative '../../spec_helper'
require_relative 'shared/now'

describe "Time.now" do
  it_behaves_like :time_now, :now
end
