# frozen_string_literal: true

begin
  require_relative "lib/csv/version"
rescue LoadError
  # for Ruby core repository
  require_relative "version"
end

Gem::Specification.new do |spec|
  spec.name          = "csv"
  spec.version       = CSV::VERSION
  spec.authors       = ["James Edward Gray II", "Kouhei Sutou"]
  spec.email         = [nil, "kou@cozmixng.org"]

  spec.summary       = "CSV Reading and Writing"
  spec.description   = "The CSV library provides a complete interface to CSV files and data. It offers tools to enable you to read and write to and from Strings or IO objects, as needed."
  spec.homepage      = "https://github.com/ruby/csv"
  spec.license       = "BSD-2-Clause"

  spec.files         = [
    "LICENSE.txt",
    "NEWS.md",
    "README.md",
    "lib/csv.rb",
    "lib/csv/core_ext/array.rb",
    "lib/csv/core_ext/string.rb",
    "lib/csv/delete_suffix.rb",
    "lib/csv/fields_converter.rb",
    "lib/csv/match_p.rb",
    "lib/csv/parser.rb",
    "lib/csv/row.rb",
    "lib/csv/table.rb",
    "lib/csv/version.rb",
    "lib/csv/writer.rb",
  ]
  spec.require_paths = ["lib"]
  spec.required_ruby_version = ">= 2.3.0"

  spec.add_development_dependency "bundler"
  spec.add_development_dependency "rake"
  spec.add_development_dependency "benchmark_driver"
  spec.add_development_dependency "simplecov"
end
