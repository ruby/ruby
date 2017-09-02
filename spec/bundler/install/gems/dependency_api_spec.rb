# frozen_string_literal: true
require "spec_helper"

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

    bundle :install, :artifice => "endpoint"
    expect(out).to include("' sinatra' is not a valid gem name because it contains whitespace.")
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

  it "should use the endpoint when using --deployment" do
    gemfile <<-G
      source "#{source_uri}"
      gem "rack"
    G
    bundle :install, :artifice => "endpoint"

    bundle "install --deployment", :artifice => "endpoint"
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
      git "file:///#{lib_path("foo-1.0")}" do
        gem 'foo'
      end
    G

    bundle :install, :artifice => "endpoint"

    expect(the_bundle).to include_gems("rails 2.3.2")
  end

  it "handles git dependencies that are in rubygems using --deployment" do
    build_git "foo" do |s|
      s.executables = "foobar"
      s.add_dependency "rails", "2.3.2"
    end

    gemfile <<-G
      source "#{source_uri}"
      gem 'foo', :git => "file:///#{lib_path("foo-1.0")}"
    G

    bundle :install, :artifice => "endpoint"

    bundle "install --deployment", :artifice => "endpoint"

    expect(the_bundle).to include_gems("rails 2.3.2")
  end

  it "doesn't fail if you only have a git gem with no deps when using --deployment" do
    build_git "foo"
    gemfile <<-G
      source "#{source_uri}"
      gem 'foo', :git => "file:///#{lib_path("foo-1.0")}"
    G

    bundle "install", :artifice => "endpoint"
    bundle "install --deployment", :artifice => "endpoint"

    expect(exitstatus).to eq(0) if exitstatus
    expect(the_bundle).to include_gems("foo 1.0")
  end

  it "falls back when the API errors out" do
    simulate_platform mswin

    gemfile <<-G
      source "#{source_uri}"
      gem "rcov"
    G

    bundle :install, :artifice => "windows"
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

    bundle :install, :artifice => "endpoint_redirect"
    expect(out).to match(/Too many redirects/)
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

      bundle "update --full-index", :artifice => "endpoint"
      expect(out).to include("Fetching source index from #{source_uri}")
      expect(the_bundle).to include_gems "rack 1.0.0"
    end
  end

  it "fetches again when more dependencies are found in subsequent sources" do
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
    expect(the_bundle).to include_gems "back_deps 1.0"
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

  it "considers all possible versions of dependencies from all api gem sources" do
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
      source "#{source_uri}/extra"
      gem "back_deps"
    G

    bundle :install, :artifice => "endpoint_extra"

    expect(out).to include("Fetching gem metadata from http://localgemserver.test/..")
    expect(out).to include("Fetching source index from http://localgemserver.test/extra")
  end

  it "does not fetch every spec if the index of gems is large when doing back deps" do
    build_repo2 do
      build_gem "back_deps" do |s|
        s.add_dependency "foo"
      end
      build_gem "missing"
      # need to hit the limit
      1.upto(Bundler::Source::Rubygems::API_REQUEST_LIMIT) do |i|
        build_gem "gem#{i}"
      end

      FileUtils.rm_rf Dir[gem_repo2("gems/foo-*.gem")]
    end

    gemfile <<-G
      source "#{source_uri}"
      source "#{source_uri}/extra"
      gem "back_deps"
    G

    bundle :install, :artifice => "endpoint_extra_missing"
    expect(the_bundle).to include_gems "back_deps 1.0"
  end

  it "uses the endpoint if all sources support it" do
    gemfile <<-G
      source "#{source_uri}"

      gem 'foo'
    G

    bundle :install, :artifice => "endpoint_api_missing"
    expect(the_bundle).to include_gems "foo 1.0"
  end

  it "fetches again when more dependencies are found in subsequent sources using --deployment" do
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

    bundle "install --deployment", :artifice => "endpoint_extra"
    expect(the_bundle).to include_gems "back_deps 1.0"
  end

  it "does not refetch if the only unmet dependency is bundler" do
    gemfile <<-G
      source "#{source_uri}"

      gem "bundler_dep"
    G

    bundle :install, :artifice => "endpoint"
    expect(out).to include("Fetching gem metadata from #{source_uri}")
  end

  it "should install when EndpointSpecification has a bin dir owned by root", :sudo => true do
    sudo "mkdir -p #{system_gem_path("bin")}"
    sudo "chown -R root #{system_gem_path("bin")}"

    gemfile <<-G
      source "#{source_uri}"
      gem "rails"
    G
    bundle :install, :artifice => "endpoint"
    expect(the_bundle).to include_gems "rails 2.3.2"
  end

  it "installs the binstubs" do
    gemfile <<-G
      source "#{source_uri}"
      gem "rack"
    G

    bundle "install --binstubs", :artifice => "endpoint"

    gembin "rackup"
    expect(out).to eq("1.0.0")
  end

  it "installs the bins when using --path and uses autoclean" do
    gemfile <<-G
      source "#{source_uri}"
      gem "rack"
    G

    bundle "install --path vendor/bundle", :artifice => "endpoint"

    expect(vendored_gems("bin/rackup")).to exist
  end

  it "installs the bins when using --path and uses bundle clean" do
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
      uri          = URI.parse(source_uri)
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

    it "strips http basic authentication creds for modern index" do
      gemfile <<-G
        source "#{basic_auth_source_uri}"
        gem "rack"
      G

      bundle :install, :artifice => "endopint_marshal_fail_basic_authentication"
      expect(out).not_to include("#{user}:#{password}")
      expect(the_bundle).to include_gems "rack 1.0.0"
    end

    it "strips http basic auth creds when it can't reach the server" do
      gemfile <<-G
        source "#{basic_auth_source_uri}"
        gem "rack"
      G

      bundle :install, :artifice => "endpoint_500"
      expect(out).not_to include("#{user}:#{password}")
    end

    it "strips http basic auth creds when warning about ambiguous sources" do
      gemfile <<-G
        source "#{basic_auth_source_uri}"
        source "file://#{gem_repo1}"
        gem "rack"
      G

      bundle :install, :artifice => "endpoint_basic_authentication"
      expect(out).to include("Warning: the gem 'rack' was found in multiple sources.")
      expect(out).not_to include("#{user}:#{password}")
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

    describe "with authentication details in bundle config" do
      before do
        gemfile <<-G
          source "#{source_uri}"
          gem "rack"
        G
      end

      it "reads authentication details by host name from bundle config" do
        bundle "config #{source_hostname} #{user}:#{password}"

        bundle :install, :artifice => "endpoint_strict_basic_authentication"

        expect(out).to include("Fetching gem metadata from #{source_uri}")
        expect(the_bundle).to include_gems "rack 1.0.0"
      end

      it "reads authentication details by full url from bundle config" do
        # The trailing slash is necessary here; Fetcher canonicalizes the URI.
        bundle "config #{source_uri}/ #{user}:#{password}"

        bundle :install, :artifice => "endpoint_strict_basic_authentication"

        expect(out).to include("Fetching gem metadata from #{source_uri}")
        expect(the_bundle).to include_gems "rack 1.0.0"
      end

      it "should use the API" do
        bundle "config #{source_hostname} #{user}:#{password}"
        bundle :install, :artifice => "endpoint_strict_basic_authentication"
        expect(out).to include("Fetching gem metadata from #{source_uri}")
        expect(the_bundle).to include_gems "rack 1.0.0"
      end

      it "prefers auth supplied in the source uri" do
        gemfile <<-G
          source "#{basic_auth_source_uri}"
          gem "rack"
        G

        bundle "config #{source_hostname} otheruser:wrong"

        bundle :install, :artifice => "endpoint_strict_basic_authentication"
        expect(the_bundle).to include_gems "rack 1.0.0"
      end

      it "shows instructions if auth is not provided for the source" do
        bundle :install, :artifice => "endpoint_strict_basic_authentication"
        expect(out).to include("bundle config #{source_hostname} username:password")
      end

      it "fails if authentication has already been provided, but failed" do
        bundle "config #{source_hostname} #{user}:wrong"

        bundle :install, :artifice => "endpoint_strict_basic_authentication"
        expect(out).to include("Bad username or password")
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

      bundle :install, :env => { "RUBYOPT" => "-I#{bundled_app("broken_ssl")}" }
      expect(out).to include("OpenSSL")
    end
  end

  context "when SSL certificate verification fails" do
    it "explains what happened" do
      # Install a monkeypatch that reproduces the effects of openssl raising
      # a certificate validation error when Rubygems tries to connect.
      gemfile <<-G
        class Net::HTTP
          def start
            raise OpenSSL::SSL::SSLError, "certificate verify failed"
          end
        end

        source "#{source_uri.gsub(/http/, "https")}"
        gem "rack"
      G

      bundle :install
      expect(out).to match(/could not verify the SSL certificate/i)
    end
  end

  context ".gemrc with sources is present" do
    before do
      File.open(home(".gemrc"), "w") do |file|
        file.puts({ :sources => ["https://rubygems.org"] }.to_yaml)
      end
    end

    after do
      home(".gemrc").rmtree
    end

    it "uses other sources declared in the Gemfile" do
      gemfile <<-G
        source "#{source_uri}"
        gem 'rack'
      G

      bundle "install", :artifice => "endpoint_marshal_fail"

      expect(exitstatus).to eq(0) if exitstatus
    end
  end
end
