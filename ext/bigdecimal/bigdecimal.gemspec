# coding: utf-8

Gem::Specification.new do |s|
  s.name          = "bigdecimal"
  s.version       = "3.1.1"
  s.authors       = ["Kenta Murata", "Zachary Scott", "Shigeo Kobayashi"]
  s.email         = ["mrkn@mrkn.jp"]

  s.summary       = "Arbitrary-precision decimal floating-point number library."
  s.description   = "This library provides arbitrary-precision decimal floating-point number class."
  s.homepage      = "https://github.com/ruby/bigdecimal"
  s.license       = "Ruby"

  s.require_paths = %w[lib]
  s.extensions    = %w[ext/bigdecimal/extconf.rb]
  s.files         = %w[
    bigdecimal.gemspec
    ext/bigdecimal/bigdecimal.c
    ext/bigdecimal/bigdecimal.h
    ext/bigdecimal/bits.h
    ext/bigdecimal/feature.h
    ext/bigdecimal/missing.c
    ext/bigdecimal/missing.h
    ext/bigdecimal/missing/dtoa.c
    ext/bigdecimal/static_assert.h
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

  s.required_ruby_version = Gem::Requirement.new(">= 2.5.0")
end
