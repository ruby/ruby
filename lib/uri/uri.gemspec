begin
  require_relative "lib/uri/version"
rescue LoadError # Fallback to load version file in ruby core repository
  require_relative "version"
end

Gem::Specification.new do |spec|
  spec.name          = "uri"
  spec.version       = URI::VERSION
  spec.authors       = ["Akira Yamada"]
  spec.email         = ["akira@ruby-lang.org"]

  spec.summary       = %q{URI is a module providing classes to handle Uniform Resource Identifiers}
  spec.description   = spec.summary

  github_link        = "https://github.com/ruby/uri"

  spec.homepage      = github_link
  spec.licenses      = ["Ruby", "BSD-2-Clause"]

  spec.required_ruby_version = '>= 2.5'

  spec.metadata = {
    "bug_tracker_uri" => "#{github_link}/issues",
    "changelog_uri" => "#{github_link}/releases",
    "documentation_uri" => "https://ruby.github.io/uri/",
    "homepage_uri" => spec.homepage,
    "source_code_uri" => github_link
  }

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files         = Dir.chdir(File.expand_path('..', __FILE__)) do
    `git ls-files -z 2>#{IO::NULL}`.split("\x0").reject do |file|
      (file == gemspec) || file.start_with?(*%w[bin/ test/ rakelib/ .github/ .gitignore Gemfile Rakefile])
    end
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]
end
