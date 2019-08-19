require_relative '../../spec_helper'
require 'getoptlong'
require_relative 'shared/get'

describe "GetoptLong#get_option" do
  it_behaves_like :getoptlong_get, :get_option
end
