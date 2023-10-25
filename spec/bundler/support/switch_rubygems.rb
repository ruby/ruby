# frozen_string_literal: true

require_relative "rubygems_version_manager"
RubygemsVersionManager.new(ENV["RGV"]).switch
