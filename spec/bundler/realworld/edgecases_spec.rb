# frozen_string_literal: true

RSpec.describe "real world edgecases", realworld: true do
  def rubygems_version(name, requirement)
    ruby <<-RUBY
      require "#{spec_dir}/support/artifice/vcr"
      require "bundler"
      require "bundler/source/rubygems/remote"
      require "bundler/fetcher"
      rubygem = Bundler.ui.silence do
        remote = Bundler::Source::Rubygems::Remote.new(Gem::URI("https://rubygems.org"))
        source = Bundler::Source::Rubygems.new
        fetcher = Bundler::Fetcher.new(remote)
        index = fetcher.specs([#{name.dump}], source)
        requirement = Gem::Requirement.create(#{requirement.dump})
        index.search(#{name.dump}).select {|spec| requirement.satisfied_by?(spec.version) }.last
      end
      if rubygem.nil?
        raise "Could not find #{name} (#{requirement}) on rubygems.org!\n" \
          "Found specs:\n\#{index.send(:specs).inspect}"
      end
      puts "#{name} (\#{rubygem.version})"
    RUBY
  end

  it "resolves dependencies correctly" do
    gemfile <<-G
      source "https://rubygems.org"

      gem 'rails', '~> 5.0'
      gem 'capybara', '~> 2.2.0'
      gem 'rack-cache', '1.2.0' # last version that works on Ruby 1.9
    G
    bundle :lock
    expect(lockfile).to include(rubygems_version("rails", "~> 5.0"))
    expect(lockfile).to include("capybara (2.2.1)")
  end

  it "installs the latest version of gxapi_rails" do
    gemfile <<-G
      source "https://rubygems.org"

      gem "sass-rails"
      gem "rails", "~> 5"
      gem "gxapi_rails", "< 0.1.0" # 0.1.0 was released way after the test was written
      gem 'rack-cache', '1.2.0' # last version that works on Ruby 1.9
    G
    bundle :lock
    expect(lockfile).to include("gxapi_rails (0.0.6)")
  end

  it "installs the latest version of i18n" do
    gemfile <<-G
      source "https://rubygems.org"

      gem "i18n", "~> 0.6.0"
      gem "activesupport", "~> 3.0"
      gem "activerecord", "~> 3.0"
      gem "builder", "~> 2.1.2"
    G
    bundle :lock
    expect(lockfile).to include(rubygems_version("i18n", "~> 0.6.0"))
    expect(lockfile).to include(rubygems_version("activesupport", "~> 3.0"))
  end

  it "outputs a helpful warning when gems have a gemspec with invalid `require_paths`" do
    install_gemfile <<-G, standalone: true, env: { "BUNDLE_FORCE_RUBY_PLATFORM" => "1" }
      source 'https://rubygems.org'
      gem "resque-scheduler", "2.2.0"
      gem "redis-namespace", "1.6.0" # for a consistent resolution including ruby 2.3.0
      gem "ruby2_keywords", "0.0.5"
    G
    expect(err).to include("resque-scheduler 2.2.0 includes a gemspec with `require_paths` set to an array of arrays. Newer versions of this gem might've already fixed this").once
  end
end
