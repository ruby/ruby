# frozen_string_literal: true

require_relative "switch_rubygems"

require_relative "rubygems_ext"
Spec::Rubygems.install_test_deps

require_relative "path"
$LOAD_PATH.unshift(File.expand_path("../../lib", __dir__)) if Spec::Path.ruby_core?
