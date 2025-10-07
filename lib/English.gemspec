Gem::Specification.new do |spec|
  spec.name          = "english"
  spec.version       = "0.8.0"
  spec.authors       = ["Yukihiro Matsumoto"]
  spec.email         = ["matz@ruby-lang.org"]

  spec.summary       = %q{Require 'English.rb' to reference global variables with less cryptic names.}
  spec.description   = %q{Require 'English.rb' to reference global variables with less cryptic names.}
  spec.homepage      = "https://github.com/ruby/English"
  spec.required_ruby_version = Gem::Requirement.new(">= 2.3.0")
  spec.licenses       = ["Ruby", "BSD-2-Clause"]

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  excludes = %W[
    :^/test :^/spec :^/feature :^/bin
    :^/Rakefile :^/Gemfile\* :^/.git*
    :^/#{File.basename(__FILE__)}
  ]
  spec.files = IO.popen(%W[git ls-files -z --] + excludes, err: IO::NULL) do |f|
    f.readlines("\x0", chomp: true)
  end
  spec.require_paths = ["lib"]
end
