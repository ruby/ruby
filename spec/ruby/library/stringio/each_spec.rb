require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative 'shared/each'

describe "StringIO#each when passed a separator" do
  it_behaves_like :stringio_each_separator, :each
end

describe "StringIO#each when passed no arguments" do
  it_behaves_like :stringio_each_no_arguments, :each
end

describe "StringIO#each when self is not readable" do
  it_behaves_like :stringio_each_not_readable, :each
end

describe "StringIO#each when passed chomp" do
  it_behaves_like :stringio_each_chomp, :each
end
