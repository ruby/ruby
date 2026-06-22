# frozen_string_literal: true

name = File.basename(__FILE__, ".gemspec")
version = ["lib", Array.new(name.count("-"), "..").join("/")].find do |dir|
  break File.foreach(File.join(__dir__, dir, "#{name.tr('-', '/')}.rb")) do |line|
    /^\s*VERSION\s*=\s*"(.*)"/ =~ line and break $1
  end rescue nil
end

Gem::Specification.new do |spec|
  spec.name          = name
  spec.version       = version
  spec.authors = ["Yukihiro Matsumoto"]
  spec.email = ["matz@ruby-lang.org"]

  spec.summary       = %q{The abstract interface for net-* client.}
  spec.description   = %q{The abstract interface for net-* client.}
  spec.homepage      = "https://github.com/ruby/net-protocol"
  spec.required_ruby_version = Gem::Requirement.new(">= 2.6.0")
  spec.licenses      = ["Ruby", "BSD-2-Clause"]

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = spec.homepage + "/releases"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  excludes = %W[/.git* /bin /test /*file /#{File.basename(__FILE__)}]
  spec.files = IO.popen(%W[git -C #{__dir__} ls-files -z --] + excludes.map {|e| ":^#{e}"}, &:read).split("\x0")
  spec.require_paths = ["lib"]

  spec.add_dependency "timeout"
end
