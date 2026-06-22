# frozen_string_literal: true

require_relative "rubygems_version_manager"
ENV["RGV"] ||= "."
RubygemsVersionManager.new(ENV["RGV"]).switch
