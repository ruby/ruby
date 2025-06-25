# frozen_string_literal: true

module Spec
  module Env
    def ruby_core?
      File.exist?(File.expand_path("../../../lib/bundler/bundler.gemspec", __dir__))
    end

    def rubylib
      ENV["RUBYLIB"].to_s.split(File::PATH_SEPARATOR)
    end
  end
end
