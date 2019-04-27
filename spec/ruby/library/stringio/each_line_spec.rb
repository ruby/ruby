require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative 'shared/each'

describe "StringIO#each_line when passed a separator" do
  it_behaves_like :stringio_each_separator, :each_line
end

describe "StringIO#each_line when passed no arguments" do
  it_behaves_like :stringio_each_no_arguments, :each_line
end

describe "StringIO#each_line when self is not readable" do
  it_behaves_like :stringio_each_not_readable, :each_line
end

describe "StringIO#each_line when passed chomp" do
  it_behaves_like :stringio_each_chomp, :each_line
end
