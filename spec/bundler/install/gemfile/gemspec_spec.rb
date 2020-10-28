# frozen_string_literal: true

RSpec.describe "bundle install from an existing gemspec" do
  before(:each) do
    build_repo2 do
      build_gem "bar"
      build_gem "bar-dev"
    end
  end

  it "should install runtime and development dependencies" do
    build_lib("foo", :path => tmp.join("foo")) do |s|
      s.write("Gemfile", "source :rubygems\ngemspec")
      s.add_dependency "bar", "=1.0.0"
      s.add_development_dependency "bar-dev", "=1.0.0"
    end
    install_gemfile <<-G
      source "#{file_uri_for(gem_repo2)}"
      gemspec :path => '#{tmp.join("foo")}'
    G

    expect(the_bundle).to include_gems "bar 1.0.0"
    expect(the_bundle).to include_gems "bar-dev 1.0.0", :groups => :development
  end

  it "that is hidden should install runtime and development dependencies" do
    build_lib("foo", :path => tmp.join("foo")) do |s|
      s.write("Gemfile", "source :rubygems\ngemspec")
      s.add_dependency "bar", "=1.0.0"
      s.add_development_dependency "bar-dev", "=1.0.0"
    end
    FileUtils.mv tmp.join("foo", "foo.gemspec"), tmp.join("foo", ".gemspec")

    install_gemfile <<-G
      source "#{file_uri_for(gem_repo2)}"
      gemspec :path => '#{tmp.join("foo")}'
    G

    expect(the_bundle).to include_gems "bar 1.0.0"
    expect(the_bundle).to include_gems "bar-dev 1.0.0", :groups => :development
  end

  it "should handle a list of requirements" do
    update_repo2 do
      build_gem "baz", "1.0"
      build_gem "baz", "1.1"
    end

    build_lib("foo", :path => tmp.join("foo")) do |s|
      s.write("Gemfile", "source :rubygems\ngemspec")
      s.add_dependency "baz", ">= 1.0", "< 1.1"
    end
    install_gemfile <<-G
      source "#{file_uri_for(gem_repo2)}"
      gemspec :path => '#{tmp.join("foo")}'
    G

    expect(the_bundle).to include_gems "baz 1.0"
  end

  it "should raise if there are no gemspecs available" do
    build_lib("foo", :path => tmp.join("foo"), :gemspec => false)

    install_gemfile <<-G, :raise_on_error => false
      source "#{file_uri_for(gem_repo2)}"
      gemspec :path => '#{tmp.join("foo")}'
    G
    expect(err).to match(/There are no gemspecs at #{tmp.join('foo')}/)
  end

  it "should raise if there are too many gemspecs available" do
    build_lib("foo", :path => tmp.join("foo")) do |s|
      s.write("foo2.gemspec", build_spec("foo", "4.0").first.to_ruby)
    end

    install_gemfile <<-G, :raise_on_error => false
      source "#{file_uri_for(gem_repo2)}"
      gemspec :path => '#{tmp.join("foo")}'
    G
    expect(err).to match(/There are multiple gemspecs at #{tmp.join('foo')}/)
  end

  it "should pick a specific gemspec" do
    build_lib("foo", :path => tmp.join("foo")) do |s|
      s.write("foo2.gemspec", "")
      s.add_dependency "bar", "=1.0.0"
      s.add_development_dependency "bar-dev", "=1.0.0"
    end

    install_gemfile(<<-G)
      source "#{file_uri_for(gem_repo2)}"
      gemspec :path => '#{tmp.join("foo")}', :name => 'foo'
    G

    expect(the_bundle).to include_gems "bar 1.0.0"
    expect(the_bundle).to include_gems "bar-dev 1.0.0", :groups => :development
  end

  it "should use a specific group for development dependencies" do
    build_lib("foo", :path => tmp.join("foo")) do |s|
      s.write("foo2.gemspec", "")
      s.add_dependency "bar", "=1.0.0"
      s.add_development_dependency "bar-dev", "=1.0.0"
    end

    install_gemfile(<<-G)
      source "#{file_uri_for(gem_repo2)}"
      gemspec :path => '#{tmp.join("foo")}', :name => 'foo', :development_group => :dev
    G

    expect(the_bundle).to include_gems "bar 1.0.0"
    expect(the_bundle).not_to include_gems "bar-dev 1.0.0", :groups => :development
    expect(the_bundle).to include_gems "bar-dev 1.0.0", :groups => :dev
  end

  it "should match a lockfile even if the gemspec defines development dependencies" do
    build_lib("foo", :path => tmp.join("foo")) do |s|
      s.write("Gemfile", "source '#{file_uri_for(gem_repo1)}'\ngemspec")
      s.add_dependency "actionpack", "=2.3.2"
      s.add_development_dependency "rake", "=13.0.1"
    end

    bundle "install", :dir => tmp.join("foo")
    # This should really be able to rely on $stderr, but, it's not written
    # right, so we can't. In fact, this is a bug negation test, and so it'll
    # ghost pass in future, and will only catch a regression if the message
    # doesn't change. Exit codes should be used correctly (they can be more
    # than just 0 and 1).
    bundle "config set --local deployment true"
    output = bundle("install", :dir => tmp.join("foo"))
    expect(output).not_to match(/You have added to the Gemfile/)
    expect(output).not_to match(/You have deleted from the Gemfile/)
    expect(output).not_to match(/install in deployment mode after changing/)
  end

  it "should match a lockfile without needing to re-resolve" do
    build_lib("foo", :path => tmp.join("foo")) do |s|
      s.add_dependency "rack"
    end

    install_gemfile <<-G
      source "#{file_uri_for(gem_repo1)}"
      gemspec :path => '#{tmp.join("foo")}'
    G

    bundle "install", :verbose => true

    message = "Found no changes, using resolution from the lockfile"
    expect(out.scan(message).size).to eq(1)
  end

  it "should match a lockfile without needing to re-resolve with development dependencies" do
    simulate_platform java

    build_lib("foo", :path => tmp.join("foo")) do |s|
      s.add_dependency "rack"
      s.add_development_dependency "thin"
    end

    install_gemfile <<-G
      source "#{file_uri_for(gem_repo1)}"
      gemspec :path => '#{tmp.join("foo")}'
    G

    bundle "install", :verbose => true

    message = "Found no changes, using resolution from the lockfile"
    expect(out.scan(message).size).to eq(1)
  end

  it "should match a lockfile on non-ruby platforms with a transitive platform dependency", :jruby do
    build_lib("foo", :path => tmp.join("foo")) do |s|
      s.add_dependency "platform_specific"
    end

    system_gems "platform_specific-1.0-java", :path => default_bundle_path

    install_gemfile <<-G
      gemspec :path => '#{tmp.join("foo")}'
    G

    bundle "update --bundler", :verbose => true
    expect(the_bundle).to include_gems "foo 1.0", "platform_specific 1.0 JAVA"
  end

  it "should evaluate the gemspec in its directory" do
    build_lib("foo", :path => tmp.join("foo"))
    File.open(tmp.join("foo/foo.gemspec"), "w") do |s|
      s.write "raise 'ahh' unless Dir.pwd == '#{tmp.join("foo")}'"
    end

    install_gemfile <<-G, :raise_on_error => false
      gemspec :path => '#{tmp.join("foo")}'
    G
    expect(last_command.stdboth).not_to include("ahh")
  end

  it "allows the gemspec to activate other gems" do
    ENV["BUNDLE_PATH__SYSTEM"] = "true"
    # see https://github.com/rubygems/bundler/issues/5409
    #
    # issue was caused by rubygems having an unresolved gem during a require,
    # so emulate that
    system_gems %w[rack-1.0.0 rack-0.9.1 rack-obama-1.0]

    build_lib("foo", :path => bundled_app)
    gemspec = bundled_app("foo.gemspec").read
    bundled_app("foo.gemspec").open("w") do |f|
      f.write "#{gemspec.strip}.tap { gem 'rack-obama'; require 'rack/obama' }"
    end

    install_gemfile <<-G
      gemspec
    G

    expect(the_bundle).to include_gem "foo 1.0"
  end

  it "allows conflicts" do
    build_lib("foo", :path => tmp.join("foo")) do |s|
      s.version = "1.0.0"
      s.add_dependency "bar", "= 1.0.0"
    end
    build_gem "deps", :to_bundle => true do |s|
      s.add_dependency "foo", "= 0.0.1"
    end
    build_gem "foo", "0.0.1", :to_bundle => true

    install_gemfile <<-G
      source "#{file_uri_for(gem_repo2)}"
      gem "deps"
      gemspec :path => '#{tmp.join("foo")}', :name => 'foo'
    G

    expect(the_bundle).to include_gems "foo 1.0.0"
  end

  it "does not break Gem.finish_resolve with conflicts" do
    build_lib("foo", :path => tmp.join("foo")) do |s|
      s.version = "1.0.0"
      s.add_dependency "bar", "= 1.0.0"
    end
    update_repo2 do
      build_gem "deps" do |s|
        s.add_dependency "foo", "= 0.0.1"
      end
      build_gem "foo", "0.0.1"
    end

    install_gemfile <<-G
      source "#{file_uri_for(gem_repo2)}"
      gem "deps"
      gemspec :path => '#{tmp.join("foo")}', :name => 'foo'
    G

    expect(the_bundle).to include_gems "foo 1.0.0"

    run "Gem.finish_resolve; puts 'WIN'"
    expect(out).to eq("WIN")
  end

  it "works with only_update_to_newer_versions" do
    build_lib "omg", "2.0", :path => lib_path("omg")

    install_gemfile <<-G
      gemspec :path => "#{lib_path("omg")}"
    G

    build_lib "omg", "1.0", :path => lib_path("omg")

    bundle :install, :env => { "BUNDLE_BUNDLE_ONLY_UPDATE_TO_NEWER_VERSIONS" => "true" }

    expect(the_bundle).to include_gems "omg 1.0"
  end

  context "in deployment mode" do
    context "when the lockfile was not updated after a change to the gemspec's dependencies" do
      it "reports that installation failed" do
        build_lib "cocoapods", :path => bundled_app do |s|
          s.add_dependency "activesupport", ">= 1"
        end

        install_gemfile <<-G
          source "#{file_uri_for(gem_repo1)}"
          gemspec
        G

        expect(the_bundle).to include_gems("cocoapods 1.0", "activesupport 2.3.5")

        build_lib "cocoapods", :path => bundled_app do |s|
          s.add_dependency "activesupport", ">= 1.0.1"
        end

        bundle "config --local deployment true"
        bundle :install, :raise_on_error => false

        expect(err).to include("changed")
      end
    end
  end

  context "when child gemspecs conflict with a released gemspec" do
    before do
      # build the "parent" gem that depends on another gem in the same repo
      build_lib "source_conflict", :path => bundled_app do |s|
        s.add_dependency "rack_middleware"
      end

      # build the "child" gem that is the same version as a released gem, but
      # has completely different and conflicting dependency requirements
      build_lib "rack_middleware", "1.0", :path => bundled_app("rack_middleware") do |s|
        s.add_dependency "rack", "1.0" # anything other than 0.9.1
      end
    end

    it "should install the child gemspec's deps" do
      install_gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
        gemspec
      G

      expect(the_bundle).to include_gems "rack 1.0"
    end
  end

  context "with a lockfile and some missing dependencies" do
    let(:source_uri) { "http://localgemserver.test" }

    context "previously bundled for Ruby" do
      let(:platform) { "ruby" }

      before do
        skip "not installing for some reason" if Gem.win_platform?

        build_lib("foo", :path => tmp.join("foo")) do |s|
          s.add_dependency "rack", "=1.0.0"
        end

        gemfile <<-G
          source "#{source_uri}"
          gemspec :path => "../foo"
        G

        lockfile <<-L
          PATH
            remote: ../foo
            specs:
              foo (1.0)
                rack (= 1.0.0)

          GEM
            remote: #{source_uri}
            specs:
              rack (1.0.0)

          PLATFORMS
            #{generic_local_platform}

          DEPENDENCIES
            foo!

          BUNDLED WITH
             #{Bundler::VERSION}
        L
      end

      context "using JRuby with explicit platform", :jruby do
        before do
          create_file(
            tmp.join("foo", "foo-java.gemspec"),
            build_spec("foo", "1.0", "java") do
              dep "rack", "=1.0.0"
              @spec.authors = "authors"
              @spec.summary = "summary"
            end.first.to_ruby
          )
        end

        it "should install" do
          results = bundle "install", :artifice => "endpoint"
          expect(results).to include("Installing rack 1.0.0")
          expect(the_bundle).to include_gems "rack 1.0.0"
        end
      end

      context "using JRuby", :jruby do
        it "should install" do
          results = bundle "install", :artifice => "endpoint"
          expect(results).to include("Installing rack 1.0.0")
          expect(the_bundle).to include_gems "rack 1.0.0"
        end
      end

      context "using Windows" do
        it "should install" do
          simulate_windows do
            results = bundle "install", :artifice => "endpoint"
            expect(results).to include("Installing rack 1.0.0")
            expect(the_bundle).to include_gems "rack 1.0.0"
          end
        end
      end
    end

    context "bundled for ruby and jruby" do
      let(:platform_specific_type) { :runtime }
      let(:dependency) { "platform_specific" }
      before do
        build_repo2 do
          build_gem "indirect_platform_specific" do |s|
            s.add_runtime_dependency "platform_specific"
          end
        end

        build_lib "foo", :path => bundled_app do |s|
          if platform_specific_type == :runtime
            s.add_runtime_dependency dependency
          elsif platform_specific_type == :development
            s.add_development_dependency dependency
          else
            raise "wrong dependency type #{platform_specific_type}, can only be :development or :runtime"
          end
        end

        bundle "config specific_platform false"

        %w[ruby jruby].each do |platform|
          simulate_platform(platform) do
            install_gemfile <<-G
              source "#{file_uri_for(gem_repo2)}"
              gemspec
            G
          end
        end
      end

      context "on ruby" do
        before do
          simulate_platform("ruby")
          bundle :install
        end

        context "as a runtime dependency" do
          it "keeps java dependencies in the lockfile" do
            expect(the_bundle).to include_gems "foo 1.0", "platform_specific 1.0 RUBY"
            expect(lockfile).to eq strip_whitespace(<<-L)
              PATH
                remote: .
                specs:
                  foo (1.0)
                    platform_specific

              GEM
                remote: #{file_uri_for(gem_repo2)}/
                specs:
                  platform_specific (1.0)
                  platform_specific (1.0-java)

              PLATFORMS
                java
                ruby

              DEPENDENCIES
                foo!

              BUNDLED WITH
                 #{Bundler::VERSION}
            L
          end
        end

        context "as a development dependency" do
          let(:platform_specific_type) { :development }

          it "keeps java dependencies in the lockfile" do
            expect(the_bundle).to include_gems "foo 1.0", "platform_specific 1.0 RUBY"
            expect(lockfile).to eq strip_whitespace(<<-L)
              PATH
                remote: .
                specs:
                  foo (1.0)

              GEM
                remote: #{file_uri_for(gem_repo2)}/
                specs:
                  platform_specific (1.0)
                  platform_specific (1.0-java)

              PLATFORMS
                java
                ruby

              DEPENDENCIES
                foo!
                platform_specific

              BUNDLED WITH
                 #{Bundler::VERSION}
            L
          end
        end

        context "with an indirect platform-specific development dependency" do
          let(:platform_specific_type) { :development }
          let(:dependency) { "indirect_platform_specific" }

          it "keeps java dependencies in the lockfile" do
            expect(the_bundle).to include_gems "foo 1.0", "indirect_platform_specific 1.0", "platform_specific 1.0 RUBY"
            expect(lockfile).to eq strip_whitespace(<<-L)
              PATH
                remote: .
                specs:
                  foo (1.0)

              GEM
                remote: #{file_uri_for(gem_repo2)}/
                specs:
                  indirect_platform_specific (1.0)
                    platform_specific
                  platform_specific (1.0)
                  platform_specific (1.0-java)

              PLATFORMS
                java
                ruby

              DEPENDENCIES
                foo!
                indirect_platform_specific

              BUNDLED WITH
                 #{Bundler::VERSION}
            L
          end
        end
      end
    end
  end

  context "with multiple platforms" do
    before do
      build_lib("foo", :path => tmp.join("foo")) do |s|
        s.version = "1.0.0"
        s.add_development_dependency "rack"
        s.write "foo-universal-java.gemspec", build_spec("foo", "1.0.0", "universal-java") {|sj| sj.runtime "rack", "1.0.0" }.first.to_ruby
      end
    end

    it "installs the ruby platform gemspec" do
      simulate_platform "ruby"

      install_gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
        gemspec :path => '#{tmp.join("foo")}', :name => 'foo'
      G

      expect(the_bundle).to include_gems "foo 1.0.0", "rack 1.0.0"
    end

    it "installs the ruby platform gemspec and skips dev deps with `without development` configured" do
      simulate_platform "ruby"

      bundle "config --local without development"
      install_gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
        gemspec :path => '#{tmp.join("foo")}', :name => 'foo'
      G

      expect(the_bundle).to include_gem "foo 1.0.0"
      expect(the_bundle).not_to include_gem "rack"
    end
  end
end
