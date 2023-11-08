# rubocop:disable Style/FrozenStringLiteralComment
# stub: foo 1.0.0 ruby lib

# The first line would be '# -*- encoding: utf-8 -*-' in a real stub gemspec

Gem::Specification.new do |s|
  s.name = "foo"
  s.version = "1.0.0"
  s.loaded_from = __FILE__
  s.extensions = "ext/foo"
  s.required_ruby_version = ">= 2.6.0"
end
# rubocop:enable Style/FrozenStringLiteralComment
