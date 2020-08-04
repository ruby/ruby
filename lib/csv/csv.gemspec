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
  spec.licenses      = ["Ruby", "BSD-2-Clause"]

  lib_path = "lib"
  spec.require_paths = [lib_path]
  files = []
  lib_dir = File.join(__dir__, lib_path)
  if File.exist?(lib_dir)
    Dir.chdir(lib_dir) do
      Dir.glob("**/*.rb").each do |file|
        files << "lib/#{file}"
      end
    end
  end
  doc_dir = File.join(__dir__, "doc")
  if File.exist?(doc_dir)
    Dir.chdir(doc_dir) do
      Dir.glob("**/*.rdoc").each do |rdoc_file|
        files << "doc/#{rdoc_file}"
      end
    end
  end
  spec.files = files
  spec.rdoc_options.concat(["--main", "README.md"])
  rdoc_files = [
    "LICENSE.txt",
    "NEWS.md",
    "README.md",
  ]
  spec.extra_rdoc_files = rdoc_files

  spec.required_ruby_version = ">= 2.5.0"

  # spec.add_dependency "stringio", ">= 0.1.3"
  spec.add_development_dependency "bundler"
  spec.add_development_dependency "rake"
  spec.add_development_dependency "benchmark_driver"
  spec.add_development_dependency "simplecov"
end
