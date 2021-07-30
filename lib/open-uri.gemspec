Gem::Specification.new do |spec|
  spec.name          = "open-uri"
  spec.version       = "0.2.0"
  spec.authors       = ["Tanaka Akira"]
  spec.email         = ["akr@fsij.org"]

  spec.summary       = %q{An easy-to-use wrapper for Net::HTTP, Net::HTTPS and Net::FTP.}
  spec.description   = %q{An easy-to-use wrapper for Net::HTTP, Net::HTTPS and Net::FTP.}
  spec.homepage      = "https://github.com/ruby/open-uri"
  spec.required_ruby_version = Gem::Requirement.new(">= 2.3.0")
  spec.licenses      = ["Ruby", "BSD-2-Clause"]

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage

  spec.files         = Dir.chdir(File.expand_path('..', __FILE__)) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  end
  spec.executables   = []
  spec.require_paths = ["lib"]

  spec.add_dependency "uri"
  spec.add_dependency "stringio"
  spec.add_dependency "time"
end
