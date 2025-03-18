# frozen_string_literal: true

require "webrick"
module Spec
  class SilentLogger < WEBrick::BasicLog
    def initialize(log_file = nil, level = nil)
      super(log_file, level || FATAL)
    end
  end
end
