# frozen_string_literal: true

require_relative "../support/rubygems_version_manager"

RubygemsVersionManager.new(ENV["RGV"]).switch

$:.delete("#{Spec::Path.spec_dir}/rubygems")

require "rubygems"
