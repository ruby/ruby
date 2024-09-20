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

  it "is able to update a top-level dependency when there is a conflict on a shared transitive child" do
    # from https://github.com/rubygems/bundler/issues/5031

    pristine_system_gems "bundler-1.99.0"

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

    bundle "lock --update paperclip", env: { "BUNDLER_VERSION" => "1.99.0" }

    expect(lockfile).to include(rubygems_version("paperclip", "~> 5.1.0"))
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

  it "doesn't hang on nix gemfile" do
    skip "Only for ruby 3.0" unless RUBY_VERSION.start_with?("3.0")

    gemfile <<~G
      source "https://rubygems.org"

      gem "addressable"
      gem "atk"
      gem "awesome_print"
      gem "bacon"
      gem "byebug"
      gem "cairo"
      gem "cairo-gobject"
      gem "camping"
      gem "charlock_holmes"
      gem "cld3"
      gem "cocoapods"
      gem "cocoapods-acknowledgements"
      gem "cocoapods-art"
      gem "cocoapods-bin"
      gem "cocoapods-browser"
      gem "cocoapods-bugsnag"
      gem "cocoapods-check"
      gem "cocoapods-clean"
      gem "cocoapods-clean_build_phases_scripts"
      gem "cocoapods-core"
      gem "cocoapods-coverage"
      gem "cocoapods-deintegrate"
      gem "cocoapods-dependencies"
      gem "cocoapods-deploy"
      gem "cocoapods-downloader"
      gem "cocoapods-expert-difficulty"
      gem "cocoapods-fix-react-native"
      gem "cocoapods-generate"
      gem "cocoapods-git_url_rewriter"
      gem "cocoapods-keys"
      gem "cocoapods-no-dev-schemes"
      gem "cocoapods-open"
      gem "cocoapods-packager"
      gem "cocoapods-playgrounds"
      gem "cocoapods-plugins"
      gem "cocoapods-prune-localizations"
      gem "cocoapods-rome"
      gem "cocoapods-search"
      gem "cocoapods-sorted-search"
      gem "cocoapods-static-swift-framework"
      gem "cocoapods-stats"
      gem "cocoapods-tdfire-binary"
      gem "cocoapods-testing"
      gem "cocoapods-trunk"
      gem "cocoapods-try"
      gem "cocoapods-try-release-fix"
      gem "cocoapods-update-if-you-dare"
      gem "cocoapods-whitelist"
      gem "cocoapods-wholemodule"
      gem "coderay"
      gem "concurrent-ruby"
      gem "curb"
      gem "curses"
      gem "daemons"
      gem "dep-selector-libgecode"
      gem "digest-sha3"
      gem "domain_name"
      gem "do_sqlite3"
      gem "ethon"
      gem "eventmachine"
      gem "excon"
      gem "faraday"
      gem "ffi"
      gem "ffi-rzmq-core"
      gem "fog-dnsimple"
      gem "gdk_pixbuf2"
      gem "gio2"
      gem "gitlab-markup"
      gem "glib2"
      gem "gpgme"
      gem "gtk2"
      gem "hashie"
      gem "highline"
      gem "hike"
      gem "hitimes"
      gem "hpricot"
      gem "httpclient"
      gem "http-cookie"
      gem "iconv"
      gem "idn-ruby"
      gem "jbuilder"
      gem "jekyll"
      gem "jmespath"
      gem "jwt"
      gem "libv8"
      gem "libxml-ruby"
      gem "magic"
      gem "markaby"
      gem "method_source"
      gem "mini_magick"
      gem "msgpack"
      gem "mysql2"
      gem "ncursesw"
      gem "netrc"
      gem "net-scp"
      gem "net-ssh"
      gem "nokogiri"
      gem "opus-ruby"
      gem "ovirt-engine-sdk"
      gem "pango"
      gem "patron"
      gem "pcaprub"
      gem "pg"
      gem "pry"
      gem "pry-byebug"
      gem "pry-doc"
      gem "public_suffix"
      gem "puma"
      gem "rails"
      gem "rainbow"
      gem "rbnacl"
      gem "rb-readline"
      gem "re2"
      gem "redis"
      gem "redis-rack"
      gem "rest-client"
      gem "rmagick"
      gem "rpam2"
      gem "rspec"
      gem "rubocop"
      gem "rubocop-performance"
      gem "ruby-libvirt"
      gem "ruby-lxc"
      gem "ruby-progressbar"
      gem "ruby-terminfo"
      gem "ruby-vips"
      gem "rubyzip"
      gem "rugged"
      gem "sassc"
      gem "scrypt"
      gem "semian"
      gem "sequel"
      gem "sequel_pg"
      gem "simplecov"
      gem "sinatra"
      gem "slop"
      gem "snappy"
      gem "sqlite3"
      gem "taglib-ruby"
      gem "thrift"
      gem "tilt"
      gem "tiny_tds"
      gem "treetop"
      gem "typhoeus"
      gem "tzinfo"
      gem "unf_ext"
      gem "uuid4r"
      gem "whois"
      gem "zookeeper"
    G

    bundle :lock, env: { "DEBUG_RESOLVER" => "1" }

    expect(out).to include("Solution found after 4 attempts")
  end
end
