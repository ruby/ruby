Gem::Specification.new do |spec|
  spec.name          = "openssl"
  spec.version       = "3.2.0"
  spec.authors       = ["Martin Bosslet", "SHIBATA Hiroshi", "Zachary Scott", "Kazuki Yamaguchi"]
  spec.email         = ["ruby-core@ruby-lang.org"]
  spec.summary       = %q{SSL/TLS and general-purpose cryptography for Ruby}
  spec.description   = %q{OpenSSL for Ruby provides access to SSL/TLS and general-purpose cryptography based on the OpenSSL library.}
  spec.homepage      = "https://github.com/ruby/openssl"
  spec.licenses      = ["Ruby", "BSD-2-Clause"]

  if Gem::Platform === spec.platform and spec.platform =~ 'java' or RUBY_ENGINE == 'jruby'
    spec.platform    = "java"
    spec.files       = []
    spec.add_runtime_dependency('jruby-openssl', '~> 0.14')
  else
    spec.files         = Dir["lib/**/*.rb", "ext/**/*.{c,h,rb}", "*.md", "BSDL", "LICENSE.txt"]
    spec.require_paths = ["lib"]
    spec.extensions    = ["ext/openssl/extconf.rb"]
  end

  spec.extra_rdoc_files = Dir["*.md"]
  spec.rdoc_options = ["--main", "README.md"]

  spec.required_ruby_version = ">= 2.7.0"

  spec.metadata["msys2_mingw_dependencies"] = "openssl"
end
