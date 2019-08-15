require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative 'shared/class_exec'

describe "Module#module_exec" do
  it_behaves_like :module_class_exec, :module_exec
end
