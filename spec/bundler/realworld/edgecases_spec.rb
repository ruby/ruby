# frozen_string_literal: true

RSpec.describe "real world edgecases", :realworld => true, :sometimes => true do
  def rubygems_version(name, requirement)
    ruby! <<-RUBY
      require #{File.expand_path("../../support/artifice/vcr.rb", __FILE__).dump}
      require "bundler"
      require "bundler/source/rubygems/remote"
      require "bundler/fetcher"
      source = Bundler::Source::Rubygems::Remote.new(URI("https://rubygems.org"))
      fetcher = Bundler::Fetcher.new(source)
      index = fetcher.specs([#{name.dump}], nil)
      rubygem = index.search(Gem::Dependency.new(#{name.dump}, #{requirement.dump})).last
      if rubygem.nil?
        raise "Could not find #{name} (#{requirement}) on rubygems.org!\n" \
          "Found specs:\n\#{index.send(:specs).inspect}"
      end
      "#{name} (\#{rubygem.version})"
    RUBY
  end

  # there is no rbx-relative-require gem that will install on 1.9
  it "ignores extra gems with bad platforms", :ruby => "~> 1.8.7" do
    gemfile <<-G
      source "https://rubygems.org"
      gem "linecache", "0.46"
    G
    bundle :lock
    expect(err).to lack_errors
    expect(exitstatus).to eq(0) if exitstatus
  end

  # https://github.com/bundler/bundler/issues/1202
  it "bundle cache works with rubygems 1.3.7 and pre gems",
    :ruby => "~> 1.8.7", :rubygems => "~> 1.3.7" do
    install_gemfile <<-G
      source "https://rubygems.org"
      gem "rack",          "1.3.0.beta2"
      gem "will_paginate", "3.0.pre2"
    G
    bundle :cache
    expect(out).not_to include("Removing outdated .gem files from vendor/cache")
  end

  # https://github.com/bundler/bundler/issues/1486
  # this is a hash collision that only manifests on 1.8.7
  it "finds the correct child versions", :ruby => "~> 1.8.7" do
    gemfile <<-G
      source "https://rubygems.org"

      gem 'i18n', '~> 0.6.0'
      gem 'activesupport', '~> 3.0.5'
      gem 'activerecord', '~> 3.0.5'
      gem 'builder', '~> 2.1.2'
    G
    bundle :lock
    expect(lockfile).to include("activemodel (3.0.5)")
  end

  it "resolves dependencies correctly", :ruby => "1.9.3" do
    gemfile <<-G
      source "https://rubygems.org"

      gem 'rails', '~> 3.0'
      gem 'capybara', '~> 2.2.0'
      gem 'rack-cache', '1.2.0' # last version that works on Ruby 1.9
    G
    bundle! :lock
    expect(lockfile).to include(rubygems_version("rails", "~> 3.0"))
    expect(lockfile).to include("capybara (2.2.1)")
  end

  it "installs the latest version of gxapi_rails", :ruby => "1.9.3" do
    gemfile <<-G
      source "https://rubygems.org"

      gem "sass-rails"
      gem "rails", "~> 3"
      gem "gxapi_rails", "< 0.1.0" # 0.1.0 was released way after the test was written
      gem 'rack-cache', '1.2.0' # last version that works on Ruby 1.9
    G
    bundle! :lock
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
    bundle! :lock
    expect(lockfile).to include(rubygems_version("i18n", "~> 0.6.0"))
    expect(lockfile).to include(rubygems_version("activesupport", "~> 3.0"))
  end

  it "is able to update a top-level dependency when there is a conflict on a shared transitive child", :ruby => "2.1" do
    # from https://github.com/bundler/bundler/issues/5031

    gemfile <<-G
      source "https://rubygems.org"
      gem 'rails', '~> 4.2.7.1'
      gem 'paperclip', '~> 5.1.0'
    G

    lockfile <<-L
      GEM
        remote: https://rubygems.org/
        specs:
          actionmailer (4.2.7.1)
            actionpack (= 4.2.7.1)
            actionview (= 4.2.7.1)
            activejob (= 4.2.7.1)
            mail (~> 2.5, >= 2.5.4)
            rails-dom-testing (~> 1.0, >= 1.0.5)
          actionpack (4.2.7.1)
            actionview (= 4.2.7.1)
            activesupport (= 4.2.7.1)
            rack (~> 1.6)
            rack-test (~> 0.6.2)
            rails-dom-testing (~> 1.0, >= 1.0.5)
            rails-html-sanitizer (~> 1.0, >= 1.0.2)
          actionview (4.2.7.1)
            activesupport (= 4.2.7.1)
            builder (~> 3.1)
            erubis (~> 2.7.0)
            rails-dom-testing (~> 1.0, >= 1.0.5)
            rails-html-sanitizer (~> 1.0, >= 1.0.2)
          activejob (4.2.7.1)
            activesupport (= 4.2.7.1)
            globalid (>= 0.3.0)
          activemodel (4.2.7.1)
            activesupport (= 4.2.7.1)
            builder (~> 3.1)
          activerecord (4.2.7.1)
            activemodel (= 4.2.7.1)
            activesupport (= 4.2.7.1)
            arel (~> 6.0)
          activesupport (4.2.7.1)
            i18n (~> 0.7)
            json (~> 1.7, >= 1.7.7)
            minitest (~> 5.1)
            thread_safe (~> 0.3, >= 0.3.4)
            tzinfo (~> 1.1)
          arel (6.0.3)
          builder (3.2.2)
          climate_control (0.0.3)
            activesupport (>= 3.0)
          cocaine (0.5.8)
            climate_control (>= 0.0.3, < 1.0)
          concurrent-ruby (1.0.2)
          erubis (2.7.0)
          globalid (0.3.7)
            activesupport (>= 4.1.0)
          i18n (0.7.0)
          json (1.8.3)
          loofah (2.0.3)
            nokogiri (>= 1.5.9)
          mail (2.6.4)
            mime-types (>= 1.16, < 4)
          mime-types (3.1)
            mime-types-data (~> 3.2015)
          mime-types-data (3.2016.0521)
          mimemagic (0.3.2)
          mini_portile2 (2.1.0)
          minitest (5.9.1)
          nokogiri (1.6.8)
            mini_portile2 (~> 2.1.0)
            pkg-config (~> 1.1.7)
          paperclip (5.1.0)
            activemodel (>= 4.2.0)
            activesupport (>= 4.2.0)
            cocaine (~> 0.5.5)
            mime-types
            mimemagic (~> 0.3.0)
          pkg-config (1.1.7)
          rack (1.6.4)
          rack-test (0.6.3)
            rack (>= 1.0)
          rails (4.2.7.1)
            actionmailer (= 4.2.7.1)
            actionpack (= 4.2.7.1)
            actionview (= 4.2.7.1)
            activejob (= 4.2.7.1)
            activemodel (= 4.2.7.1)
            activerecord (= 4.2.7.1)
            activesupport (= 4.2.7.1)
            bundler (>= 1.3.0, < 2.0)
            railties (= 4.2.7.1)
            sprockets-rails
          rails-deprecated_sanitizer (1.0.3)
            activesupport (>= 4.2.0.alpha)
          rails-dom-testing (1.0.7)
            activesupport (>= 4.2.0.beta, < 5.0)
            nokogiri (~> 1.6.0)
            rails-deprecated_sanitizer (>= 1.0.1)
          rails-html-sanitizer (1.0.3)
            loofah (~> 2.0)
          railties (4.2.7.1)
            actionpack (= 4.2.7.1)
            activesupport (= 4.2.7.1)
            rake (>= 0.8.7)
            thor (>= 0.18.1, < 2.0)
          rake (11.3.0)
          sprockets (3.7.0)
            concurrent-ruby (~> 1.0)
            rack (> 1, < 3)
          sprockets-rails (3.2.0)
            actionpack (>= 4.0)
            activesupport (>= 4.0)
            sprockets (>= 3.0.0)
          thor (0.19.1)
          thread_safe (0.3.5)
          tzinfo (1.2.2)
            thread_safe (~> 0.1)

      PLATFORMS
        ruby

      DEPENDENCIES
        paperclip (~> 5.1.0)
        rails (~> 4.2.7.1)
    L

    bundle! "lock --update paperclip"

    expect(lockfile).to include(rubygems_version("paperclip", "~> 5.1.0"))
  end

  # https://github.com/bundler/bundler/issues/1500
  it "does not fail install because of gem plugins" do
    realworld_system_gems("open_gem --version 1.4.2", "rake --version 0.9.2")
    gemfile <<-G
      source "https://rubygems.org"

      gem 'rack', '1.0.1'
    G

    bundle! :install, forgotten_command_line_options(:path => "vendor/bundle")
    expect(err).not_to include("Could not find rake")
    expect(err).to lack_errors
  end

  it "checks out git repos when the lockfile is corrupted" do
    gemfile <<-G
      source "https://rubygems.org"
      git_source(:github) {|repo| "https://github.com/\#{repo}.git" }

      gem 'activerecord',  :github => 'carlhuda/rails-bundler-test', :branch => 'master'
      gem 'activesupport', :github => 'carlhuda/rails-bundler-test', :branch => 'master'
      gem 'actionpack',    :github => 'carlhuda/rails-bundler-test', :branch => 'master'
    G

    lockfile <<-L
      GIT
        remote: https://github.com/carlhuda/rails-bundler-test.git
        revision: 369e28a87419565f1940815219ea9200474589d4
        branch: master
        specs:
          actionpack (3.2.2)
            activemodel (= 3.2.2)
            activesupport (= 3.2.2)
            builder (~> 3.0.0)
            erubis (~> 2.7.0)
            journey (~> 1.0.1)
            rack (~> 1.4.0)
            rack-cache (~> 1.2)
            rack-test (~> 0.6.1)
            sprockets (~> 2.1.2)
          activemodel (3.2.2)
            activesupport (= 3.2.2)
            builder (~> 3.0.0)
          activerecord (3.2.2)
            activemodel (= 3.2.2)
            activesupport (= 3.2.2)
            arel (~> 3.0.2)
            tzinfo (~> 0.3.29)
          activesupport (3.2.2)
            i18n (~> 0.6)
            multi_json (~> 1.0)

      GIT
        remote: https://github.com/carlhuda/rails-bundler-test.git
        revision: 369e28a87419565f1940815219ea9200474589d4
        branch: master
        specs:
          actionpack (3.2.2)
            activemodel (= 3.2.2)
            activesupport (= 3.2.2)
            builder (~> 3.0.0)
            erubis (~> 2.7.0)
            journey (~> 1.0.1)
            rack (~> 1.4.0)
            rack-cache (~> 1.2)
            rack-test (~> 0.6.1)
            sprockets (~> 2.1.2)
          activemodel (3.2.2)
            activesupport (= 3.2.2)
            builder (~> 3.0.0)
          activerecord (3.2.2)
            activemodel (= 3.2.2)
            activesupport (= 3.2.2)
            arel (~> 3.0.2)
            tzinfo (~> 0.3.29)
          activesupport (3.2.2)
            i18n (~> 0.6)
            multi_json (~> 1.0)

      GIT
        remote: https://github.com/carlhuda/rails-bundler-test.git
        revision: 369e28a87419565f1940815219ea9200474589d4
        branch: master
        specs:
          actionpack (3.2.2)
            activemodel (= 3.2.2)
            activesupport (= 3.2.2)
            builder (~> 3.0.0)
            erubis (~> 2.7.0)
            journey (~> 1.0.1)
            rack (~> 1.4.0)
            rack-cache (~> 1.2)
            rack-test (~> 0.6.1)
            sprockets (~> 2.1.2)
          activemodel (3.2.2)
            activesupport (= 3.2.2)
            builder (~> 3.0.0)
          activerecord (3.2.2)
            activemodel (= 3.2.2)
            activesupport (= 3.2.2)
            arel (~> 3.0.2)
            tzinfo (~> 0.3.29)
          activesupport (3.2.2)
            i18n (~> 0.6)
            multi_json (~> 1.0)

      GEM
        remote: https://rubygems.org/
        specs:
          arel (3.0.2)
          builder (3.0.0)
          erubis (2.7.0)
          hike (1.2.1)
          i18n (0.6.0)
          journey (1.0.3)
          multi_json (1.1.0)
          rack (1.4.1)
          rack-cache (1.2)
            rack (>= 0.4)
          rack-test (0.6.1)
            rack (>= 1.0)
          sprockets (2.1.2)
            hike (~> 1.2)
            rack (~> 1.0)
            tilt (~> 1.1, != 1.3.0)
          tilt (1.3.3)
          tzinfo (0.3.32)

      PLATFORMS
        ruby

      DEPENDENCIES
        actionpack!
        activerecord!
        activesupport!
    L

    bundle! :lock
    expect(last_command.stderr).to lack_errors
  end

  it "outputs a helpful error message when gems have invalid gemspecs" do
    install_gemfile <<-G, :standalone => true
      source 'https://rubygems.org'
      gem "resque-scheduler", "2.2.0"
    G
    expect(out).to include("You have one or more invalid gemspecs that need to be fixed.")
    expect(out).to include("resque-scheduler 2.2.0 has an invalid gemspec")
  end
end
