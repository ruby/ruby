require_relative '../../spec_helper'
require_relative 'shared/rfc2822'
require 'time'

describe "Time.rfc822" do
  it_behaves_like :time_rfc2822, :rfc822
end
