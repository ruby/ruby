require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative 'shared/write'

describe "StringIO#syswrite when passed [Object]" do
  it_behaves_like :stringio_write, :syswrite
end

describe "StringIO#syswrite when passed [String]" do
  it_behaves_like :stringio_write_string, :syswrite
end

describe "StringIO#syswrite when self is not writable" do
  it_behaves_like :stringio_write_not_writable, :syswrite
end

describe "StringIO#syswrite when in append mode" do
  it_behaves_like :stringio_write_append, :syswrite
end
