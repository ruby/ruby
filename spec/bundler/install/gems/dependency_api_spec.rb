# frozen_string_literal: true

RSpec.describe "gemcutter's dependency API" do
  let(:source_hostname) { "localgemserver.test" }
  let(:source_uri) { "http://#{source_hostname}" }

  it "should use the API" do
    gemfile <<-G
      source "#{source_uri}"
      gem "rack"
    G

    bundle :install, :artifice => "endpoint"
    expect(out).to include("Fetching gem metadata from #{source_uri}")
    expect(the_bundle).to include_gems "rack 1.0.0"
  end

  it "should URI encode gem names" do
    gemfile <<-G
      source "#{source_uri}"
      gem " sinatra"
    G

    bundle :install, :artifice => "endpoint", :raise_on_error => false
    expect(err).to include("' sinatra' is not a valid gem name because it contains whitespace.")
  end

  it "should handle nested dependencies" do
    gemfile <<-G
      source "#{source_uri}"
      gem "rails"
    G

    bundle :install, :artifice => "endpoint"
    expect(out).to include("Fetching gem metadata from #{source_uri}/...")
    expect(the_bundle).to include_gems(
      "rails 2.3.2",
      "actionpack 2.3.2",
      "activerecord 2.3.2",
      "actionmailer 2.3.2",
      "activeresource 2.3.2",
      "activesupport 2.3.2"
    )
  end

  it "should handle multiple gem dependencies on the same gem" do
    gemfile <<-G
      source "#{source_uri}"
      gem "net-sftp"
    G

    bundle :install, :artifice => "endpoint"
    expect(the_bundle).to include_gems "net-sftp 1.1.1"
  end

  it "should use the endpoint when using deployment mode" do
    gemfile <<-G
      source "#{source_uri}"
      gem "rack"
    G
    bundle :install, :artifice => "endpoint"

    bundle "config set --local deployment true"
    bundle "config set --local path vendor/bundle"
    bundle :install, :artifice => "endpoint"
    expect(out).to include("Fetching gem metadata from #{source_uri}")
    expect(the_bundle).to include_gems "rack 1.0.0"
  end

  it "handles git dependencies that are in rubygems" do
    build_git "foo" do |s|
      s.executables = "foobar"
      s.add_dependency "rails", "2.3.2"
    end

    gemfile <<-G
      source "#{source_uri}"
      git "#{file_uri_for(lib_path("foo-1.0"))}" do
        gem 'foo'
      end
    G

    bundle :install, :artifice => "endpoint"

    expect(the_bundle).to include_gems("rails 2.3.2")
  end

  it "handles git dependencies that are in rubygems using deployment mode" do
    build_git "foo" do |s|
      s.executables = "foobar"
      s.add_dependency "rails", "2.3.2"
    end

    gemfile <<-G
      source "#{source_uri}"
      gem 'foo', :git => "#{file_uri_for(lib_path("foo-1.0"))}"
    G

    bundle :install, :artifice => "endpoint"

    bundle "config set --local deployment true"
    bundle :install, :artifice => "endpoint"

    expect(the_bundle).to include_gems("rails 2.3.2")
  end

  it "doesn't fail if you only have a git gem with no deps when using deployment mode" do
    build_git "foo"
    gemfile <<-G
      source "#{source_uri}"
      gem 'foo', :git => "#{file_uri_for(lib_path("foo-1.0"))}"
    G

    bundle "install", :artifice => "endpoint"
    bundle "config set --local deployment true"
    bundle :install, :artifice => "endpoint"

    expect(the_bundle).to include_gems("foo 1.0")
  end

  it "falls back when the API errors out" do
    simulate_platform x86_mswin32

    build_repo2 do
      # The rcov gem is platform mswin32, but has no arch
      build_gem "rcov" do |s|
        s.platform = Gem::Platform.new([nil, "mswin32", nil])
        s.write "lib/rcov.rb", "RCOV = '1.0.0'"
      end
    end

    gemfile <<-G
      source "#{source_uri}"
      gem "rcov"
    G

    bundle :install, :artifice => "windows", :env => { "BUNDLER_SPEC_GEM_REPO" => gem_repo2.to_s }
    expect(out).to include("Fetching source index from #{source_uri}")
    expect(the_bundle).to include_gems "rcov 1.0.0"
  end

  it "falls back when hitting the Gemcutter Dependency Limit" do
    gemfile <<-G
      source "#{source_uri}"
      gem "activesupport"
      gem "actionpack"
      gem "actionmailer"
      gem "activeresource"
      gem "thin"
      gem "rack"
      gem "rails"
    G
    bundle :install, :artifice => "endpoint_fallback"
    expect(out).to include("Fetching source index from #{source_uri}")

    expect(the_bundle).to include_gems(
      "activesupport 2.3.2",
      "actionpack 2.3.2",
      "actionmailer 2.3.2",
      "activeresource 2.3.2",
      "activesupport 2.3.2",
      "thin 1.0.0",
      "rack 1.0.0",
      "rails 2.3.2"
    )
  end

  it "falls back when Gemcutter API doesn't return proper Marshal format" do
    gemfile <<-G
      source "#{source_uri}"
      gem "rack"
    G

    bundle :install, :verbose => true, :artifice => "endpoint_marshal_fail"
    expect(out).to include("could not fetch from the dependency API, trying the full index")
    expect(the_bundle).to include_gems "rack 1.0.0"
  end

  it "falls back when the API URL returns 403 Forbidden" do
    gemfile <<-G
      source "#{source_uri}"
      gem "rack"
    G

    bundle :install, :verbose => true, :artifice => "endpoint_api_forbidden"
    expect(out).to include("Fetching source index from #{source_uri}")
    expect(the_bundle).to include_gems "rack 1.0.0"
  end

  it "handles host redirects" do
    gemfile <<-G
      source "#{source_uri}"
      gem "rack"
    G

    bundle :install, :artifice => "endpoint_host_redirect"
    expect(the_bundle).to include_gems "rack 1.0.0"
  end

  it "handles host redirects without Net::HTTP::Persistent" do
    gemfile <<-G
      source "#{source_uri}"
      gem "rack"
    G

    FileUtils.mkdir_p lib_path
    File.open(lib_path("disable_net_http_persistent.rb"), "w") do |h|
      h.write <<-H
        module Kernel
          alias require_without_disabled_net_http require
          def require(*args)
            raise LoadError, 'simulated' if args.first == 'openssl' && !caller.grep(/vendored_persistent/).empty?
            require_without_disabled_net_http(*args)
          end
        end
      H
    end

    bundle :install, :artifice => "endpoint_host_redirect", :requires => [lib_path("disable_net_http_persistent.rb")]
    expect(out).to_not match(/Too many redirects/)
    expect(the_bundle).to include_gems "rack 1.0.0"
  end

  it "timeouts when Bundler::Fetcher redirects too much" do
    gemfile <<-G
      source "#{source_uri}"
      gem "rack"
    G

    bundle :install, :artifice => "endpoint_redirect", :raise_on_error => false
    expect(err).to match(/Too many redirects/)
  end

  context "when --full-index is specified" do
    it "should use the modern index for install" do
      gemfile <<-G
        source "#{source_uri}"
        gem "rack"
      G

      bundle "install --full-index", :artifice => "endpoint"
      expect(out).to include("Fetching source index from #{source_uri}")
      expect(the_bundle).to include_gems "rack 1.0.0"
    end

    it "should use the modern index for update" do
      gemfile <<-G
        source "#{source_uri}"
        gem "rack"
      G

      bundle "update --full-index", :artifice => "endpoint", :all => true
      expect(out).to include("Fetching source index from #{source_uri}")
      expect(the_bundle).to include_gems "rack 1.0.0"
    end
  end

  it "fetches again when more dependencies are found in subsequent sources", :bundler => "< 3" do
    build_repo2 do
      build_gem "back_deps" do |s|
        s.add_dependency "foo"
      end
      FileUtils.rm_rf Dir[gem_repo2("gems/foo-*.gem")]
    end

    gemfile <<-G
      source "#{source_uri}"
      source "#{source_uri}/extra"
      gem "back_deps"
    G

    bundle :install, :artifice => "endpoint_extra"
    expect(the_bundle).to include_gems "back_deps 1.0", "foo 1.0"
  end

  it "fetches again when more dependencies are found in subsequent sources using blocks" do
    build_repo2 do
      build_gem "back_deps" do |s|
        s.add_dependency "foo"
      end
      FileUtils.rm_rf Dir[gem_repo2("gems/foo-*.gem")]
    end

    gemfile <<-G
      source "#{source_uri}"
      source "#{source_uri}/extra" do
        gem "back_deps"
      end
    G

    bundle :install, :artifice => "endpoint_extra"
    expect(the_bundle).to include_gems "back_deps 1.0", "foo 1.0"
  end

  it "fetches gem versions even when those gems are already installed" do
    gemfile <<-G
      source "#{source_uri}"
      gem "rack", "1.0.0"
    G
    bundle :install, :artifice => "endpoint_extra_api"

    build_repo4 do
      build_gem "rack", "1.2" do |s|
        s.executables = "rackup"
      end
    end

    gemfile <<-G
      source "#{source_uri}" do; end
      source "#{source_uri}/extra"
      gem "rack", "1.2"
    G
    bundle :install, :artifice => "endpoint_extra_api"
    expect(the_bundle).to include_gems "rack 1.2"
  end

  it "considers all possible versions of dependencies from all api gem sources", :bundler => "< 3" do
    # In this scenario, the gem "somegem" only exists in repo4.  It depends on specific version of activesupport that
    # exists only in repo1.  There happens also be a version of activesupport in repo4, but not the one that version 1.0.0
    # of somegem wants. This test makes sure that bundler actually finds version 1.2.3 of active support in the other
    # repo and installs it.
    build_repo4 do
      build_gem "activesupport", "1.2.0"
      build_gem "somegem", "1.0.0" do |s|
        s.add_dependency "activesupport", "1.2.3" # This version exists only in repo1
      end
    end

    gemfile <<-G
      source "#{source_uri}"
      source "#{source_uri}/extra"
      gem 'somegem', '1.0.0'
    G

    bundle :install, :artifice => "endpoint_extra_api"

    expect(the_bundle).to include_gems "somegem 1.0.0"
    expect(the_bundle).to include_gems "activesupport 1.2.3"
  end

  it "prints API output properly with back deps" do
    build_repo2 do
      build_gem "back_deps" do |s|
        s.add_dependency "foo"
      end
      FileUtils.rm_rf Dir[gem_repo2("gems/foo-*.gem")]
    end

    gemfile <<-G
      source "#{source_uri}"
      source "#{source_uri}/extra" do
        gem "back_deps"
      end
    G

    bundle :install, :artifice => "endpoint_extra"

    expect(out).to include("Fetching gem metadata from http://localgemserver.test/.")
    expect(out).to include("Fetching source index from http://localgemserver.test/extra")
  end

  it "does not fetch every spec when doing back deps", :bundler => "< 3" do
    build_repo2 do
      build_gem "back_deps" do |s|
        s.add_dependency "foo"
      end
      build_gem "missing"

      FileUtils.rm_rf Dir[gem_repo2("gems/foo-*.gem")]
    end

    install_gemfile <<-G, :artifice => "endpoint_extra_missing", :env => env_for_missing_prerelease_default_gem_activation
      source "#{source_uri}"
      source "#{source_uri}/extra"
      gem "back_deps"
    G

    expect(the_bundle).to include_gems "back_deps 1.0"
  end

  it "does not fetch every spec when doing back deps using blocks" do
    build_repo2 do
      build_gem "back_deps" do |s|
        s.add_dependency "foo"
      end
      build_gem "missing"

      FileUtils.rm_rf Dir[gem_repo2("gems/foo-*.gem")]
    end

    install_gemfile <<-G, :artifice => "endpoint_extra_missing", :env => env_for_missing_prerelease_default_gem_activation
      source "#{source_uri}"
      source "#{source_uri}/extra" do
        gem "back_deps"
      end
    G

    expect(the_bundle).to include_gems "back_deps 1.0"
  end

  it "fetches again when more dependencies are found in subsequent sources using deployment mode", :bundler => "< 3" do
    build_repo2 do
      build_gem "back_deps" do |s|
        s.add_dependency "foo"
      end
      FileUtils.rm_rf Dir[gem_repo2("gems/foo-*.gem")]
    end

    gemfile <<-G
      source "#{source_uri}"
      source "#{source_uri}/extra"
      gem "back_deps"
    G

    bundle :install, :artifice => "endpoint_extra"
    bundle "config set --local deployment true"
    bundle :install, :artifice => "endpoint_extra"
    expect(the_bundle).to include_gems "back_deps 1.0"
  end

  it "fetches again when more dependencies are found in subsequent sources using deployment mode with blocks" do
    build_repo2 do
      build_gem "back_deps" do |s|
        s.add_dependency "foo"
      end
      FileUtils.rm_rf Dir[gem_repo2("gems/foo-*.gem")]
    end

    gemfile <<-G
      source "#{source_uri}"
      source "#{source_uri}/extra" do
        gem "back_deps"
      end
    G

    bundle :install, :artifice => "endpoint_extra"
    bundle "config set --local deployment true"
    bundle "install", :artifice => "endpoint_extra"
    expect(the_bundle).to include_gems "back_deps 1.0"
  end

  it "does not fetch all marshaled specs" do
    build_repo2 do
      build_gem "foo", "1.0"
      build_gem "foo", "2.0"
    end

    install_gemfile <<-G, :artifice => "endpoint", :env => { "BUNDLER_SPEC_GEM_REPO" => gem_repo2.to_s }, :verbose => true
      source "#{source_uri}"

      gem "foo"
    G

    expect(out).to include("foo-2.0.gemspec.rz")
    expect(out).not_to include("foo-1.0.gemspec.rz")
  end

  it "does not refetch if the only unmet dependency is bundler" do
    build_repo2 do
      build_gem "bundler_dep" do |s|
        s.add_dependency "bundler"
      end
    end

    gemfile <<-G
      source "#{source_uri}"

      gem "bundler_dep"
    G

    bundle :install, :artifice => "endpoint", :env => { "BUNDLER_SPEC_GEM_REPO" => gem_repo2.to_s }
    expect(out).to include("Fetching gem metadata from #{source_uri}")
  end

  it "installs the binstubs", :bundler => "< 3" do
    gemfile <<-G
      source "#{source_uri}"
      gem "rack"
    G

    bundle "install --binstubs", :artifice => "endpoint"

    gembin "rackup"
    expect(out).to eq("1.0.0")
  end

  it "installs the bins when using --path and uses autoclean", :bundler => "< 3" do
    gemfile <<-G
      source "#{source_uri}"
      gem "rack"
    G

    bundle "install --path vendor/bundle", :artifice => "endpoint"

    expect(vendored_gems("bin/rackup")).to exist
  end

  it "installs the bins when using --path and uses bundle clean", :bundler => "< 3" do
    gemfile <<-G
      source "#{source_uri}"
      gem "rack"
    G

    bundle "install --path vendor/bundle --no-clean", :artifice => "endpoint"

    expect(vendored_gems("bin/rackup")).to exist
  end

  it "prints post_install_messages" do
    gemfile <<-G
      source "#{source_uri}"
      gem 'rack-obama'
    G

    bundle :install, :artifice => "endpoint"
    expect(out).to include("Post-install message from rack:")
  end

  it "should display the post install message for a dependency" do
    gemfile <<-G
      source "#{source_uri}"
      gem 'rack_middleware'
    G

    bundle :install, :artifice => "endpoint"
    expect(out).to include("Post-install message from rack:")
    expect(out).to include("Rack's post install message")
  end

  context "when using basic authentication" do
    let(:user)     { "user" }
    let(:password) { "pass" }
    let(:basic_auth_source_uri) do
      uri          = Bundler::URI.parse(source_uri)
      uri.user     = user
      uri.password = password

      uri
    end

    it "passes basic authentication details and strips out creds" do
      gemfile <<-G
        source "#{basic_auth_source_uri}"
        gem "rack"
      G

      bundle :install, :artifice => "endpoint_basic_authentication"
      expect(out).not_to include("#{user}:#{password}")
      expect(the_bundle).to include_gems "rack 1.0.0"
    end

    it "passes basic authentication details and strips out creds also in verbose mode" do
      gemfile <<-G
        source "#{basic_auth_source_uri}"
        gem "rack"
      G

      bundle :install, :verbose => true, :artifice => "endpoint_basic_authentication"
      expect(out).not_to include("#{user}:#{password}")
      expect(the_bundle).to include_gems "rack 1.0.0"
    end

    it "strips http basic authentication creds for modern index" do
      gemfile <<-G
        source "#{basic_auth_source_uri}"
        gem "rack"
      G

      bundle :install, :artifice => "endpoint_marshal_fail_basic_authentication"
      expect(out).not_to include("#{user}:#{password}")
      expect(the_bundle).to include_gems "rack 1.0.0"
    end

    it "strips http basic auth creds when it can't reach the server" do
      gemfile <<-G
        source "#{basic_auth_source_uri}"
        gem "rack"
      G

      bundle :install, :artifice => "endpoint_500", :raise_on_error => false
      expect(out).not_to include("#{user}:#{password}")
    end

    it "strips http basic auth creds when warning about ambiguous sources", :bundler => "< 3" do
      gemfile <<-G
        source "#{basic_auth_source_uri}"
        source "#{file_uri_for(gem_repo1)}"
        gem "rack"
      G

      bundle :install, :artifice => "endpoint_basic_authentication"
      expect(err).to include("Warning: the gem 'rack' was found in multiple sources.")
      expect(err).not_to include("#{user}:#{password}")
      expect(the_bundle).to include_gems "rack 1.0.0"
    end

    it "does not pass the user / password to different hosts on redirect" do
      gemfile <<-G
        source "#{basic_auth_source_uri}"
        gem "rack"
      G

      bundle :install, :artifice => "endpoint_creds_diff_host"
      expect(the_bundle).to include_gems "rack 1.0.0"
    end

    describe "with host including dashes" do
      before do
        gemfile <<-G
          source "http://local-gemserver.test"
          gem "rack"
        G
      end

      it "reads authentication details from a valid ENV variable" do
        bundle :install, :artifice => "endpoint_strict_basic_authentication", :env => { "BUNDLE_LOCAL___GEMSERVER__TEST" => "#{user}:#{password}" }

        expect(out).to include("Fetching gem metadata from http://local-gemserver.test")
        expect(the_bundle).to include_gems "rack 1.0.0"
      end
    end

    describe "with authentication details in bundle config" do
      before do
        gemfile <<-G
          source "#{source_uri}"
          gem "rack"
        G
      end

      it "reads authentication details by host name from bundle config" do
        bundle "config set #{source_hostname} #{user}:#{password}"

        bundle :install, :artifice => "endpoint_strict_basic_authentication"

        expect(out).to include("Fetching gem metadata from #{source_uri}")
        expect(the_bundle).to include_gems "rack 1.0.0"
      end

      it "reads authentication details by full url from bundle config" do
        # The trailing slash is necessary here; Fetcher canonicalizes the URI.
        bundle "config set #{source_uri}/ #{user}:#{password}"

        bundle :install, :artifice => "endpoint_strict_basic_authentication"

        expect(out).to include("Fetching gem metadata from #{source_uri}")
        expect(the_bundle).to include_gems "rack 1.0.0"
      end

      it "should use the API" do
        bundle "config set #{source_hostname} #{user}:#{password}"
        bundle :install, :artifice => "endpoint_strict_basic_authentication"
        expect(out).to include("Fetching gem metadata from #{source_uri}")
        expect(the_bundle).to include_gems "rack 1.0.0"
      end

      it "prefers auth supplied in the source uri" do
        gemfile <<-G
          source "#{basic_auth_source_uri}"
          gem "rack"
        G

        bundle "config set #{source_hostname} otheruser:wrong"

        bundle :install, :artifice => "endpoint_strict_basic_authentication"
        expect(the_bundle).to include_gems "rack 1.0.0"
      end

      it "shows instructions if auth is not provided for the source" do
        bundle :install, :artifice => "endpoint_strict_basic_authentication", :raise_on_error => false
        expect(err).to include("bundle config set --global #{source_hostname} username:password")
      end

      it "fails if authentication has already been provided, but failed" do
        bundle "config set #{source_hostname} #{user}:wrong"

        bundle :install, :artifice => "endpoint_strict_basic_authentication", :raise_on_error => false
        expect(err).to include("Bad username or password")
      end
    end

    describe "with no password" do
      let(:password) { nil }

      it "passes basic authentication details" do
        gemfile <<-G
          source "#{basic_auth_source_uri}"
          gem "rack"
        G

        bundle :install, :artifice => "endpoint_basic_authentication"
        expect(the_bundle).to include_gems "rack 1.0.0"
      end
    end
  end

  context "when ruby is compiled without openssl" do
    before do
      # Install a monkeypatch that reproduces the effects of openssl being
      # missing when the fetcher runs, as happens in real life. The reason
      # we can't just overwrite openssl.rb is that Artifice uses it.
      bundled_app("broken_ssl").mkpath
      bundled_app("broken_ssl/openssl.rb").open("w") do |f|
        f.write <<-RUBY
          raise LoadError, "cannot load such file -- openssl"
        RUBY
      end
    end

    it "explains what to do to get it" do
      gemfile <<-G
        source "#{source_uri.gsub(/http/, "https")}"
        gem "rack"
      G

      bundle :install, :env => { "RUBYOPT" => opt_add("-I#{bundled_app("broken_ssl")}", ENV["RUBYOPT"]) }, :raise_on_error => false
      expect(err).to include("OpenSSL")
    end
  end

  context "when SSL certificate verification fails" do
    it "explains what happened" do
      # Install a monkeypatch that reproduces the effects of openssl raising
      # a certificate validation error when RubyGems tries to connect.
      gemfile <<-G
        class Net::HTTP
          def start
            raise OpenSSL::SSL::SSLError, "certificate verify failed"
          end
        end

        source "#{source_uri.gsub(/http/, "https")}"
        gem "rack"
      G

      bundle :install, :raise_on_error => false
      expect(err).to match(/could not verify the SSL certificate/i)
    end
  end

  context ".gemrc with sources is present" do
    it "uses other sources declared in the Gemfile" do
      File.open(home(".gemrc"), "w") do |file|
        file.puts({ :sources => ["https://rubygems.org"] }.to_yaml)
      end

      begin
        gemfile <<-G
          source "#{source_uri}"
          gem 'rack'
        G

        bundle "install", :artifice => "endpoint_marshal_fail"
      ensure
        home(".gemrc").rmtree
      end
    end
  end
end
