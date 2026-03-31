require_relative "../../spec_helper"
require_relative 'shared/target'

describe "Refinement#target" do
  it_behaves_like :refinement_target, :target
end
