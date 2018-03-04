require_relative '../../spec_helper'
require_relative 'shared/rfc2822'
require 'time'

describe "Time.rfc2822" do
  it_behaves_like :time_rfc2822, :rfc2822
end
