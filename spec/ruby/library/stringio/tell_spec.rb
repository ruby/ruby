require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative 'shared/tell'

describe "StringIO#tell" do
  it_behaves_like :stringio_tell, :tell
end
