# frozen_string_literal: true

RSpec.describe "bundle install from an existing gemspec" do
  before(:each) do
    build_repo2 do
      build_gem "bar"
      build_gem "bar-dev"
    end
  end

  let(:x64_mingw_archs) do
    if RUBY_PLATFORM == "x64-mingw-ucrt"
      if Gem.rubygems_version >= Gem::Version.new("3.2.28")
        ["x64-mingw-ucrt", "x64-mingw32"]
      else
        ["x64-mingw32", "x64-unknown"]
      end
    else
      ["x64-mingw32"]
    end
  end

  let(:x64_mingw_gems) do
    x64_mingw_archs.map {|p| "platform_specific (1.0-#{p})" }.join("\n    ")
  end

  let(:x64_mingw_platforms) do
    x64_mingw_archs.join("\n  ")
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
    expect(err).to match(/There are no gemspecs at #{tmp.join("foo")}/)
  end

  it "should raise if there are too many gemspecs available" do
    build_lib("foo", :path => tmp.join("foo")) do |s|
      s.write("foo2.gemspec", build_spec("foo", "4.0").first.to_ruby)
    end

    install_gemfile <<-G, :raise_on_error => false
      source "#{file_uri_for(gem_repo2)}"
      gemspec :path => '#{tmp.join("foo")}'
    G
    expect(err).to match(/There are multiple gemspecs at #{tmp.join("foo")}/)
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
    expect(output).not_to match(/the lockfile can't be updated because frozen mode is set/)
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

  it "should match a lockfile on non-ruby platforms with a transitive platform dependency", :jruby_only do
    build_lib("foo", :path => tmp.join("foo")) do |s|
      s.add_dependency "platform_specific"
    end

    system_gems "platform_specific-1.0-java", :path => default_bundle_path

    install_gemfile <<-G
      gemspec :path => '#{tmp.join("foo")}'
    G

    bundle "update --bundler", :artifice => "compact_index", :verbose => true
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
      source "#{file_uri_for(gem_repo1)}"
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

  it "handles downgrades" do
    build_lib "omg", "2.0", :path => lib_path("omg")

    install_gemfile <<-G
      source "#{file_uri_for(gem_repo1)}"
      gemspec :path => "#{lib_path("omg")}"
    G

    build_lib "omg", "1.0", :path => lib_path("omg")

    bundle :install

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

        bundle "config set --local deployment true"
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

    before do
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

    context "using JRuby with explicit platform", :jruby_only do
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

    it "should install", :jruby do
      results = bundle "install", :artifice => "endpoint"
      expect(results).to include("Installing rack 1.0.0")
      expect(the_bundle).to include_gems "rack 1.0.0"
    end

    context "bundled for multiple platforms" do
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

        gemfile <<-G
          source "#{file_uri_for(gem_repo2)}"
          gemspec
        G

        bundle "config set --local force_ruby_platform true"
        bundle "install"

        simulate_new_machine
        simulate_platform("jruby") { bundle "install" }
        simulate_platform(x64_mingw32) { bundle "install" }
      end

      context "on ruby" do
        before do
          bundle "config set --local force_ruby_platform true"
          bundle :install
        end

        context "as a runtime dependency" do
          it "keeps all platform dependencies in the lockfile" do
            expect(the_bundle).to include_gems "foo 1.0", "platform_specific 1.0 RUBY"

            expected_checksums = construct_checksum_section do |c|
              c.repo_gem gem_repo2, "platform_specific", "1.0"
              c.repo_gem gem_repo2, "platform_specific", "1.0", x64_mingw32
            end

            expect(lockfile).to eq <<~L
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
                  #{x64_mingw_gems}

              PLATFORMS
                java
                ruby
                #{x64_mingw_platforms}

              DEPENDENCIES
                foo!

              CHECKSUMS
                foo (1.0)
                #{expected_checksums}

              BUNDLED WITH
                 #{Bundler::VERSION}
            L
          end
        end

        context "as a development dependency" do
          let(:platform_specific_type) { :development }

          it "keeps all platform dependencies in the lockfile" do
            expect(the_bundle).to include_gems "foo 1.0", "platform_specific 1.0 RUBY"

            expected_checksums = construct_checksum_section do |c|
              c.repo_gem gem_repo2, "platform_specific", "1.0"
              c.repo_gem gem_repo2, "platform_specific", "1.0", x64_mingw32
            end

            expect(lockfile).to eq <<~L
              PATH
                remote: .
                specs:
                  foo (1.0)

              GEM
                remote: #{file_uri_for(gem_repo2)}/
                specs:
                  platform_specific (1.0)
                  platform_specific (1.0-java)
                  #{x64_mingw_gems}

              PLATFORMS
                java
                ruby
                #{x64_mingw_platforms}

              DEPENDENCIES
                foo!
                platform_specific

              CHECKSUMS
                foo (1.0)
                #{expected_checksums}

              BUNDLED WITH
                 #{Bundler::VERSION}
            L
          end
        end

        context "with an indirect platform-specific development dependency" do
          let(:platform_specific_type) { :development }
          let(:dependency) { "indirect_platform_specific" }

          it "keeps all platform dependencies in the lockfile" do
            expect(the_bundle).to include_gems "foo 1.0", "indirect_platform_specific 1.0", "platform_specific 1.0 RUBY"

            expected_checksums = construct_checksum_section do |c|
              c.repo_gem gem_repo2, "indirect_platform_specific", "1.0"
              c.repo_gem gem_repo2, "platform_specific", "1.0"
              c.repo_gem gem_repo2, "platform_specific", "1.0", x64_mingw32
            end

            expect(lockfile).to eq <<~L
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
                  #{x64_mingw_gems}

              PLATFORMS
                java
                ruby
                #{x64_mingw_platforms}

              DEPENDENCIES
                foo!
                indirect_platform_specific

              CHECKSUMS
                foo (1.0)
                #{expected_checksums}

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
      bundle "config set --local force_ruby_platform true"

      install_gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
        gemspec :path => '#{tmp.join("foo")}', :name => 'foo'
      G

      expect(the_bundle).to include_gems "foo 1.0.0", "rack 1.0.0"
    end

    it "installs the ruby platform gemspec and skips dev deps with `without development` configured" do
      bundle "config set --local force_ruby_platform true"

      bundle "config set --local without development"
      install_gemfile <<-G
        source "#{file_uri_for(gem_repo1)}"
        gemspec :path => '#{tmp.join("foo")}', :name => 'foo'
      G

      expect(the_bundle).to include_gem "foo 1.0.0"
      expect(the_bundle).not_to include_gem "rack"
    end
  end

  context "with multiple platforms and resolving for more specific platforms" do
    before do
      build_lib("chef", :path => tmp.join("chef")) do |s|
        s.version = "17.1.17"
        s.write "chef-universal-mingw32.gemspec", build_spec("chef", "17.1.17", "universal-mingw32") {|sw| sw.runtime "win32-api", "~> 1.5.3" }.first.to_ruby
      end
    end

    it "does not remove the platform specific specs from the lockfile when updating" do
      build_repo4 do
        build_gem "win32-api", "1.5.3" do |s|
          s.platform = "universal-mingw32"
        end
      end

      gemfile <<-G
        source "#{file_uri_for(gem_repo4)}"
        gemspec :path => "../chef"
      G

      initial_lockfile = <<~L
        PATH
          remote: ../chef
          specs:
            chef (17.1.17)
            chef (17.1.17-universal-mingw32)
              win32-api (~> 1.5.3)

        GEM
          remote: #{file_uri_for(gem_repo4)}/
          specs:
            win32-api (1.5.3-universal-mingw32)

        PLATFORMS
          ruby
          #{x64_mingw_platforms}
          x86-mingw32

        DEPENDENCIES
          chef!

        CHECKSUMS
          chef (17.1.17)
          chef (17.1.17-universal-mingw32)
          #{checksum_for_repo_gem gem_repo4, "win32-api", "1.5.3", "universal-mingw32"}

        BUNDLED WITH
           #{Bundler::VERSION}
      L

      lockfile initial_lockfile

      bundle "update"

      expect(lockfile).to eq initial_lockfile
    end
  end

  context "with multiple locked platforms" do
    before do
      build_lib("activeadmin", :path => tmp.join("activeadmin")) do |s|
        s.version = "2.9.0"
        s.add_dependency "railties", ">= 5.2", "< 6.2"
      end

      build_repo4 do
        build_gem "railties", "6.1.4"

        build_gem "jruby-openssl", "0.10.7" do |s|
          s.platform = "java"
        end
      end

      install_gemfile <<-G
        source "#{file_uri_for(gem_repo4)}"
        gemspec :path => "../activeadmin"
        gem "jruby-openssl", :platform => :jruby
      G

      bundle "lock --add-platform java"
    end

    it "does not remove the platform specific specs from the lockfile when re-resolving due to gemspec changes" do
      expect(lockfile).to eq <<~L
        PATH
          remote: ../activeadmin
          specs:
            activeadmin (2.9.0)
              railties (>= 5.2, < 6.2)

        GEM
          remote: #{file_uri_for(gem_repo4)}/
          specs:
            jruby-openssl (0.10.7-java)
            railties (6.1.4)

        PLATFORMS
          #{lockfile_platforms("java")}

        DEPENDENCIES
          activeadmin!
          jruby-openssl

        CHECKSUMS
          activeadmin (2.9.0)
          #{checksum_for_repo_gem gem_repo4, "railties", "6.1.4"}

        BUNDLED WITH
           #{Bundler::VERSION}
      L

      gemspec = tmp.join("activeadmin/activeadmin.gemspec")
      File.write(gemspec, File.read(gemspec).sub(">= 5.2", ">= 6.0"))

      previous_lockfile = lockfile

      bundle "install --local"

      expect(lockfile).to eq(previous_lockfile.sub(">= 5.2", ">= 6.0"))
    end
  end
end
