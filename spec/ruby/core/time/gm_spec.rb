require_relative '../../spec_helper'
require_relative 'shared/gm'
require_relative 'shared/time_params'

describe "Time.gm" do
  it_behaves_like :time_gm, :gm
  it_behaves_like :time_params, :gm
  it_behaves_like :time_params_10_arg, :gm
  it_behaves_like :time_params_microseconds, :gm
end
