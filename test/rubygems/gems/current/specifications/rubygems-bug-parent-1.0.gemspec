# -*- encoding: utf-8 -*-

Gem::Specification.new do |s|
  s.name = %q{rubygems-bug-parent}
  s.version = "1.0"

  s.required_rubygems_version = Gem::Requirement.new(">= 0") if s.respond_to? :required_rubygems_version=
  s.authors = ["Yehuda Katz"]
  s.date = %q{2010-04-12}
  s.description = %q{Demonstrates a rubygems bug that exists in 1.9 because of gem prelude but not 1.8}
  s.email = %q{wycats@gmail.com}
  s.files = ["lib/rubygems-bug-parent.rb"]
  s.homepage = %q{http://www.yehudakatz.com}
  s.require_paths = ["lib"]
  s.required_ruby_version = Gem::Requirement.new(">= 1.8.7")
  s.rubyforge_project = %q{rubygems-bug}
  s.rubygems_version = %q{1.3.6}
  s.summary = %q{Demonstrates a rubygems bug}

  if s.respond_to? :specification_version then
    current_version = Gem::Specification::CURRENT_SPECIFICATION_VERSION
    s.specification_version = 3

    if Gem::Version.new(Gem::RubyGemsVersion) >= Gem::Version.new('1.2.0') then
      s.add_runtime_dependency(%q<rubygems-bug-child>, ["= 1.0.0"])
    else
      s.add_dependency(%q<rubygems-bug-child>, ["= 1.0.0"])
    end
  else
    s.add_dependency(%q<rubygems-bug-child>, ["= 1.0.0"])
  end
end
