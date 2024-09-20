# frozen_string_literal: true

module Spec
  module Env
    def ruby_core?
      File.exist?(File.expand_path("../../../lib/bundler/bundler.gemspec", __dir__))
    end
  end
end
