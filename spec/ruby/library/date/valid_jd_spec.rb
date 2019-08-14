require_relative '../../spec_helper'
require_relative 'shared/valid_jd'
require 'date'

describe "Date.valid_jd?" do

  it_behaves_like :date_valid_jd?, :valid_jd?

end
