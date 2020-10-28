# frozen_string_literal: true

RSpec.describe "real world edgecases", :realworld => true, :sometimes => true do
  def rubygems_version(name, requirement)
    ruby <<-RUBY
      require "#{spec_dir}/support/artifice/vcr"
      require "#{lib_dir}/bundler"
      require "#{lib_dir}/bundler/source/rubygems/remote"
      require "#{lib_dir}/bundler/fetcher"
      rubygem = Bundler.ui.silence do
        source = Bundler::Source::Rubygems::Remote.new(Bundler::URI("https://rubygems.org"))
        fetcher = Bundler::Fetcher.new(source)
        index = fetcher.specs([#{name.dump}], nil)
        index.search(Gem::Dependency.new(#{name.dump}, #{requirement.dump})).last
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

  it "is able to update a top-level dependency when there is a conflict on a shared transitive child" do
    # from https://github.com/rubygems/bundler/issues/5031

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
            bundler (>= 1.3.0, < 3.0)
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

    bundle "lock --update paperclip"

    expect(lockfile).to include(rubygems_version("paperclip", "~> 5.1.0"))
  end

  # https://github.com/rubygems/bundler/issues/1500
  it "does not fail install because of gem plugins" do
    realworld_system_gems("open_gem --version 1.4.2", "rake --version 0.9.2")
    gemfile <<-G
      source "https://rubygems.org"

      gem 'rack', '1.0.1'
    G

    bundle "config set --local path vendor/bundle"
    bundle :install
    expect(err).not_to include("Could not find rake")
    expect(err).to be_empty
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

    bundle :lock
    expect(err).to be_empty
  end

  it "outputs a helpful error message when gems have invalid gemspecs" do
    install_gemfile <<-G, :standalone => true, :raise_on_error => false
      source 'https://rubygems.org'
      gem "resque-scheduler", "2.2.0"
      gem "redis-namespace", "1.6.0" # for a consistent resolution including ruby 2.3.0
    G
    expect(err).to include("You have one or more invalid gemspecs that need to be fixed.")
    expect(err).to include("resque-scheduler 2.2.0 has an invalid gemspec")
  end
end
