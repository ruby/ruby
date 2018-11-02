# frozen_string_literal: true

module Bundler
  def self.require_thor_actions
    Kernel.send(:require, "bundler/vendor/thor/lib/thor/actions")
  end
end
require "bundler/vendor/thor/lib/thor"
