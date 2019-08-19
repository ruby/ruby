require_relative '../../spec_helper'
require_relative 'shared/valid_commercial'
require 'date'

describe "Date#valid_commercial?" do

  it_behaves_like :date_valid_commercial?, :valid_commercial?
end
