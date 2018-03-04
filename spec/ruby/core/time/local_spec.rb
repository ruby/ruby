require_relative '../../spec_helper'
require_relative 'shared/local'
require_relative 'shared/time_params'

describe "Time.local" do
  it_behaves_like :time_local, :local
  it_behaves_like :time_local_10_arg, :local
  it_behaves_like :time_params, :local
  it_behaves_like :time_params_10_arg, :local
  it_behaves_like :time_params_microseconds, :local
end
