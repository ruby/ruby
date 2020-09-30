# -*- encoding: utf-8 -*-
require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative '../../shared/string/end_with'

describe "String#end_with?" do
  it_behaves_like :end_with, :to_s
end
