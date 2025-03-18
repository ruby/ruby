# frozen_string_literal: true
Gem::Specification.new do |spec|
  spec.name = "win32-registry"
  spec.version = "0.1.0"
  spec.authors = ["U.Nakamura"]
  spec.email = ["usa@garbagecollect.jp"]

  spec.summary = %q{Provides an interface to the Windows Registry in Ruby}
  spec.description = spec.summary
  spec.homepage = "https://github.com/ruby/win32-registry"
  spec.required_ruby_version = ">= 2.6.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  excludes = %w[
    bin/ test/ spec/ features/ rakelib/
    .git .github .mailmap appveyor Rakefile Gemfile
  ]
  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |f|
      File.identical?(f, __FILE__) || f.start_with?(*excludes)
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "fiddle", "~> 1.0"
end
