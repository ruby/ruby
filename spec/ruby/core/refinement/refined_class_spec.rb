require_relative "../../spec_helper"
require_relative 'shared/target'

describe "Refinement#refined_class" do
  ruby_version_is "3.2"..."3.3" do
    it_behaves_like :refinement_target, :refined_class
  end

  ruby_version_is "3.3"..."3.4" do
    it "has been deprecated in favour of Refinement#target" do
      refinement_int = nil

      Module.new do
        refine Integer do
          refinement_int = self
        end
      end

      -> {
        refinement_int.refined_class
      }.should complain(/warning: Refinement#refined_class is deprecated and will be removed in Ruby 3.4; use Refinement#target instead/)
    end
  end

  ruby_version_is "3.4" do
    it "has been removed" do
      refinement_int = nil

      Module.new do
        refine Integer do
          refinement_int = self
        end
      end

      refinement_int.should_not.respond_to?(:refined_class)
    end
  end
end
