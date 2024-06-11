# frozen_string_literal: true

module Spec
  module Env
    def ruby_core?
      !ENV["GEM_COMMAND"].nil?
    end
  end
end
