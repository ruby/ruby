# frozen_string_literal: true

class RequirementChecker < Proc
  def self.against(present)
    provided = Gem::Version.new(present)

    new do |required|
      !Gem::Requirement.new(required).satisfied_by?(provided)
    end.tap do |checker|
      checker.provided = provided
    end
  end

  attr_accessor :provided

  def inspect
    "\"!= #{provided}\""
  end
end
