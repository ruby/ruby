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

  # Ruby bundled test/unit is a compatibility layer for minitest,
  # and it doesn't have support for minitest 5.
  s.add_runtime_dependency "minitest", '< 5.0.0'
end
