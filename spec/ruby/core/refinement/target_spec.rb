require_relative "../../spec_helper"
require_relative 'shared/target'

describe "Refinement#target" do
  ruby_version_is "3.3" do
    it_behaves_like :refinement_target, :target
  end
end
