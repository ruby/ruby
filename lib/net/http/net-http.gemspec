# frozen_string_literal: true

name = File.basename(__FILE__, ".gemspec")
version = ["lib", Array.new(name.count("-")+1, "..").join("/")].find do |dir|
  file = File.join(__dir__, dir, "#{name.tr('-', '/')}.rb")
  begin
    break File.foreach(file, mode: "rb") do |line|
      /^\s*VERSION\s*=\s*"(.*)"/ =~ line and break $1
    end
  rescue SystemCallError
    next
  end
end

Gem::Specification.new do |spec|
  spec.name          = name
  spec.version       = version
  spec.authors       = ["NARUSE, Yui"]
  spec.email         = ["naruse@airemix.jp"]

  spec.summary       = %q{HTTP client api for Ruby.}
  spec.description   = %q{HTTP client api for Ruby.}
  spec.homepage      = "https://github.com/ruby/net-http"
  spec.required_ruby_version = Gem::Requirement.new(">= 2.7.0")
  spec.licenses      = ["Ruby", "BSD-2-Clause"]

  spec.metadata["changelog_uri"] = spec.homepage + "/releases"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  excludes = %W[/.git* /bin /test /*file /#{File.basename(__FILE__)}]
  spec.files = IO.popen(%W[git -C #{__dir__} ls-files -z --] + excludes.map {|e| ":^#{e}"}, &:read).split("\x0")
  spec.bindir        = "exe"
  spec.require_paths = ["lib"]

  spec.add_dependency "uri", ">= 0.11.1"
end
