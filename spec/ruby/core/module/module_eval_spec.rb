require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative 'shared/class_eval'

describe "Module#module_eval" do
  it_behaves_like :module_class_eval, :module_eval
end
