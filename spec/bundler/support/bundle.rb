# frozen_string_literal: true

require_relative "path"

warn "#{__FILE__} is deprecated. Please use #{Spec::Path.dev_binstub} instead"

load Spec::Path.dev_binstub
