# frozen_string_literal: true

module Spec
  module CodeClimate
    def self.setup
      require "codeclimate-test-reporter"
      ::CodeClimate::TestReporter.start
      configure_exclusions
    rescue LoadError
      # it's fine if CodeClimate isn't set up
      nil
    end

    def self.configure_exclusions
      SimpleCov.start do
        add_filter "/bin/"
        add_filter "/lib/bundler/man/"
        add_filter "/lib/bundler/vendor/"
        add_filter "/man/"
        add_filter "/pkg/"
        add_filter "/spec/"
        add_filter "/tmp/"
      end
    end
  end
end
