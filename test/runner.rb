# frozen_string_literal: true

# Should be done in rubygems test files?
ENV["GEM_SKIP"] = "".freeze
ENV.delete("RUBY_CODESIGN")

Warning[:experimental] = false

gem_path = [
  File.realdirpath(".bundle"),
  File.realdirpath("../.bundle", __dir__),
]
ENV["GEM_PATH"] = gem_path.join(File::PATH_SEPARATOR)
ENV["GEM_HOME"] = gem_path.first

require_relative '../tool/test/runner'
