# frozen_string_literal: true

name = File.basename(__FILE__, ".gemspec")
version = ["lib", Array.new(name.count("-")+1, "..").join("/")].find do |dir|
  break File.foreach(File.join(__dir__, dir, "#{name.tr('-', '/')}.rb")) do |line|
    /^\s*VERSION\s*=\s*"(.*)"/ =~ line and break $1
  end rescue nil
end

Gem::Specification.new do |spec|
  spec.name          = name
  spec.version       = version
  spec.authors = ["Yukihiro Matsumoto"]
  spec.email = ["matz@ruby-lang.org"]

  spec.summary       = %q{Allows a referenced object to be garbage-collected.}
  spec.description   = %q{Allows a referenced object to be garbage-collected.}
  spec.homepage      = "https://github.com/ruby/weakref"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/ruby/weakref"
  spec.licenses      = ["Ruby", "BSD-2-Clause"]

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files         = Dir.chdir(File.expand_path('..', __FILE__)) do
    `git ls-files -z 2>/dev/null`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "delegate"
end
