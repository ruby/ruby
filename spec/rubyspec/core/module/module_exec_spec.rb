require File.expand_path('../../../spec_helper', __FILE__)
require File.expand_path('../fixtures/classes', __FILE__)
require File.expand_path('../shared/class_exec', __FILE__)

describe "Module#module_exec" do
  it_behaves_like :module_class_exec, :module_exec
end
