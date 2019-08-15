require_relative '../../spec_helper'
require_relative 'shared/valid_ordinal'
require 'date'

describe "Date.valid_ordinal?" do

  it_behaves_like :date_valid_ordinal?, :valid_ordinal?

end
