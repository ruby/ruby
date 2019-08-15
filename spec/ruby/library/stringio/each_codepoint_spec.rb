# -*- encoding: utf-8 -*-
require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative 'shared/codepoints'

# See redmine #1667
describe "StringIO#each_codepoint" do
  it_behaves_like :stringio_codepoints, :codepoints
end
