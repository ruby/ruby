require_relative '../../spec_helper'
require_relative 'shared/quote'

describe "Regexp.quote" do
  it_behaves_like :regexp_quote, :quote
end
