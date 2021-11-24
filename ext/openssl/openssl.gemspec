Gem::Specification.new do |spec|
  spec.name          = "openssl"
  spec.version       = "2.1.3"
  spec.authors       = ["Martin Bosslet", "SHIBATA Hiroshi", "Zachary Scott", "Kazuki Yamaguchi"]
  spec.email         = ["ruby-core@ruby-lang.org"]
  spec.summary       = %q{OpenSSL provides SSL, TLS and general purpose cryptography.}
  spec.description   = %q{It wraps the OpenSSL library.}
  spec.homepage      = "https://github.com/ruby/openssl"
  spec.license       = "Ruby"

  spec.files         = Dir["lib/**/*.rb", "ext/**/*.{c,h,rb}", "*.md", "BSDL", "LICENSE.txt"]
  spec.require_paths = ["lib"]
  spec.extensions    = ["ext/openssl/extconf.rb"]

  spec.extra_rdoc_files = Dir["*.md"]
  spec.rdoc_options = ["--main", "README.md"]

  spec.required_ruby_version = ">= 2.3.0"

  spec.add_runtime_dependency "ipaddr"
  spec.add_development_dependency "rake"
  spec.add_development_dependency "rake-compiler"
  spec.add_development_dependency "test-unit", "~> 3.0"
  spec.add_development_dependency "rdoc"

  spec.metadata["msys2_mingw_dependencies"] = "openssl"
end
