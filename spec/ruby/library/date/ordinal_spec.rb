require 'date'
require_relative '../../spec_helper'
require_relative 'shared/ordinal'

describe "Date.ordinal" do
  it_behaves_like :date_ordinal, :ordinal
end
