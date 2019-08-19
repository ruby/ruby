require_relative '../../spec_helper'
require_relative 'shared/quote'

describe "Regexp.escape" do
  it_behaves_like :regexp_quote, :escape
end
