# -*- encoding: utf-8 -*-
$:.unshift File.expand_path('../lib', __FILE__)
require 'mspec/version'

Gem::Specification.new do |gem|
  gem.name          = "mspec"
  gem.version       = MSpec::VERSION.to_s
  gem.authors       = ["Brian Shirai"]
  gem.email         = ["bshirai@engineyard.com"]
  gem.homepage      = "http://rubyspec.org"

  gem.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) unless File.extname(f) == ".bat" }.compact
  gem.files         = `git ls-files`.split("\n")
  gem.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  gem.require_paths = ["lib"]
  gem.description   = <<-EOD
MSpec is a specialized framework for RubySpec.
                      EOD
  gem.summary       = <<-EOS
MSpec is a specialized framework that is syntax-compatible
with RSpec for basic things like describe, it blocks and
before, after actions.

MSpec contains additional features that assist in writing
the RubySpecs used by multiple Ruby implementations. Also,
MSpec attempts to use the simplest Ruby language features
so that beginning Ruby implementations can run it.
                      EOS
  gem.has_rdoc                  = true
  gem.extra_rdoc_files          = %w[ README.md LICENSE ]
  gem.rubygems_version  = %q{1.3.5}
  gem.rubyforge_project         = 'http://rubyforge.org/projects/mspec'

  gem.rdoc_options  << '--title' << 'MSpec Gem' <<
                    '--main' << 'README.md' <<
                    '--line-numbers'

  gem.add_development_dependency "rake",   "~> 10.0"
  gem.add_development_dependency "rspec",  "~> 2.14.1"
end
