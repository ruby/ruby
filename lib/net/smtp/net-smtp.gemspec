begin
  require_relative "lib/net/smtp/version"
rescue LoadError # Fallback to load version file in ruby core repository
  require_relative "version"
end

Gem::Specification.new do |spec|
  spec.name          = "net-smtp"
  spec.version       = Net::SMTP::VERSION
  spec.authors       = ["Yukihiro Matsumoto"]
  spec.email         = ["matz@ruby-lang.org"]

  spec.summary       = %q{Simple Mail Transfer Protocol client library for Ruby.}
  spec.description   = %q{Simple Mail Transfer Protocol client library for Ruby.}
  spec.homepage      = "https://github.com/ruby/net-smtp"
  spec.license       = "BSD-2-Clause"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage

  spec.files         = Dir.chdir(File.expand_path('..', __FILE__)) do
    `git ls-files -z 2>/dev/null`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]
end
