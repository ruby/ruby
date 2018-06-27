require_relative '../../spec_helper'
require_relative 'shared/valid_civil'
require 'date'

describe "Date#valid_civil?" do

  it_behaves_like :date_valid_civil?, :valid_civil?

end
