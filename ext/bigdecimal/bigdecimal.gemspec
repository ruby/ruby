# coding: utf-8

bigdecimal_version = '1.4.1'

Gem::Specification.new do |s|
  s.name          = "bigdecimal"
  s.version       = bigdecimal_version
  s.authors       = ["Kenta Murata", "Zachary Scott", "Shigeo Kobayashi"]
  s.email         = ["mrkn@mrkn.jp"]

  s.summary       = "Arbitrary-precision decimal floating-point number library."
  s.description   = "This library provides arbitrary-precision decimal floating-point number class."
  s.homepage      = "https://github.com/ruby/bigdecimal"
  s.license       = "ruby"

  s.require_paths = %w[lib]
  s.extensions    = %w[ext/bigdecimal/extconf.rb ext/bigdecimal/util/extconf.rb]
  s.files         = %w[
    bigdecimal.gemspec
    ext/bigdecimal/bigdecimal.c
    ext/bigdecimal/bigdecimal.def
    ext/bigdecimal/bigdecimal.h
    ext/bigdecimal/depend
    ext/bigdecimal/extconf.rb
    ext/bigdecimal/util/extconf.rb
    ext/bigdecimal/util/util.c
    lib/bigdecimal.rb
    lib/bigdecimal/jacobian.rb
    lib/bigdecimal/ludcmp.rb
    lib/bigdecimal/math.rb
    lib/bigdecimal/newton.rb
    lib/bigdecimal/util.rb
    sample/linear.rb
    sample/nlsolve.rb
    sample/pi.rb
  ]

  s.required_ruby_version = Gem::Requirement.new(">= 2.3.0".freeze)

  s.add_development_dependency "rake", "~> 10.0"
  s.add_development_dependency "rake-compiler", ">= 0.9"
  s.add_development_dependency "rake-compiler-dock", ">= 0.6.1"
  s.add_development_dependency "minitest", "< 5.0.0"
  s.add_development_dependency "pry"
end
