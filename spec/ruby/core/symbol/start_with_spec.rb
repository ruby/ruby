# -*- encoding: utf-8 -*-
require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative '../../shared/string/start_with'

describe "Symbol#start_with?" do
  it_behaves_like :start_with, :to_sym
end
