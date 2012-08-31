# -*- ruby -*-

Gem::Specification.new do |s|
  s.name = "test-unit"
  s.version = "#{RUBY_VERSION}.0"
  s.homepage = "http://www.ruby-lang.org"
  s.author = "Shota Fukumori"
  s.email = "sorah@tubusu.net"
  s.summary = "test/unit compatible API testing framework"
  s.description =
    "This library implements test/unit compatible API on minitest. " +
    "The test/unit means that test/unit which was bundled with Ruby 1.8."
  s.executables = ["testrb"]
end
