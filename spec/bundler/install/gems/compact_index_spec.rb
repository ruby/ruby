# frozen_string_literal: true
require "spec_helper"

RSpec.describe "compact index api" do
  let(:source_hostname) { "localgemserver.test" }
  let(:source_uri) { "http://#{source_hostname}" }

  it "should use the API" do
    gemfile <<-G
      source "#{source_uri}"
      gem "rack"
    G

    bundle! :install, :artifice => "compact_index"
    expect(out).to include("Fetching gem metadata from #{source_uri}")
    expect(the_bundle).to include_gems "rack 1.0.0"
  end

  it "should URI encode gem names" do
    gemfile <<-G
      source "#{source_uri}"
      gem " sinatra"
    G

    bundle :install, :artifice => "compact_index"
    expect(out).to include("' sinatra' is not a valid gem name because it contains whitespace.")
  end

  it "should handle nested dependencies" do
    gemfile <<-G
      source "#{source_uri}"
      gem "rails"
    G

    bundle! :install, :artifice => "compact_index"
    expect(out).to include("Fetching gem metadata from #{source_uri}")
    expect(the_bundle).to include_gems(
      "rails 2.3.2",
      "actionpack 2.3.2",
      "activerecord 2.3.2",
      "actionmailer 2.3.2",
      "activeresource 2.3.2",
      "activesupport 2.3.2"
    )
  end

  it "should handle case sensitivity conflicts" do
    build_repo4 do
      build_gem "rack", "1.0" do |s|
        s.add_runtime_dependency("Rack", "0.1")
      end
      build_gem "Rack", "0.1"
    end

    install_gemfile! <<-G, :artifice => "compact_index", :env => { "BUNDLER_SPEC_GEM_REPO" => gem_repo4 }
      source "#{source_uri}"
      gem "rack", "1.0"
      gem "Rack", "0.1"
    G

    # can't use `include_gems` here since the `require` will conflict on a
    # case-insensitive FS
    run! "Bundler.require; puts Gem.loaded_specs.values_at('rack', 'Rack').map(&:full_name)"
    expect(out).to eq("rack-1.0\nRack-0.1")
  end

  it "should handle multiple gem dependencies on the same gem" do
    gemfile <<-G
      source "#{source_uri}"
      gem "net-sftp"
    G

    bundle! :install, :artifice => "compact_index"
    expect(the_bundle).to include_gems "net-sftp 1.1.1"
  end

  it "should use the endpoint when using --deployment" do
    gemfile <<-G
      source "#{source_uri}"
      gem "rack"
    G
    bundle! :install, :artifice => "compact_index"

    bundle "install --deployment", :artifice => "compact_index"
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

    bundle! :install, :artifice => "compact_index"

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

    bundle! :install, :artifice => "compact_index"

    bundle "install --deployment", :artifice => "compact_index"

    expect(the_bundle).to include_gems("rails 2.3.2")
  end

  it "doesn't fail if you only have a git gem with no deps when using --deployment" do
    build_git "foo"
    gemfile <<-G
      source "#{source_uri}"
      gem 'foo', :git => "file:///#{lib_path("foo-1.0")}"
    G

    bundle "install", :artifice => "compact_index"
    bundle "install --deployment", :artifice => "compact_index"

    expect(exitstatus).to eq(0) if exitstatus
    expect(the_bundle).to include_gems("foo 1.0")
  end

  it "falls back when the API errors out" do
    simulate_platform mswin

    gemfile <<-G
      source "#{source_uri}"
      gem "rcov"
    G

    bundle! :install, :artifice => "windows"
    expect(out).to include("Fetching source index from #{source_uri}")
    expect(the_bundle).to include_gems "rcov 1.0.0"
  end

  it "falls back when the API URL returns 403 Forbidden" do
    gemfile <<-G
      source "#{source_uri}"
      gem "rack"
    G

    bundle! :install, :verbose => true, :artifice => "compact_index_forbidden"
    expect(out).to include("Fetching gem metadata from #{source_uri}")
    expect(the_bundle).to include_gems "rack 1.0.0"
  end

  it "falls back when the versions endpoint has a checksum mismatch" do
    gemfile <<-G
      source "#{source_uri}"
      gem "rack"
    G

    bundle! :install, :verbose => true, :artifice => "compact_index_checksum_mismatch"
    expect(out).to include("Fetching gem metadata from #{source_uri}")
    expect(out).to include <<-'WARN'
The checksum of /versions does not match the checksum provided by the server! Something is wrong (local checksum is "\"d41d8cd98f00b204e9800998ecf8427e\"", was expecting "\"123\"").
    WARN
    expect(the_bundle).to include_gems "rack 1.0.0"
  end

  it "falls back when the user's home directory does not exist or is not writable" do
    ENV["HOME"] = nil

    gemfile <<-G
      source "#{source_uri}"
      gem "rack"
    G

    bundle! :install, :artifice => "compact_index"
    expect(out).to include("Fetching gem metadata from #{source_uri}")
    expect(the_bundle).to include_gems "rack 1.0.0"
  end

  it "handles host redirects" do
    gemfile <<-G
      source "#{source_uri}"
      gem "rack"
    G

    bundle! :install, :artifice => "compact_index_host_redirect"
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

    bundle! :install, :artifice => "compact_index_host_redirect", :requires => [lib_path("disable_net_http_persistent.rb")]
    expect(out).to_not match(/Too many redirects/)
    expect(the_bundle).to include_gems "rack 1.0.0"
  end

  it "times out when Bundler::Fetcher redirects too much" do
    gemfile <<-G
      source "#{source_uri}"
      gem "rack"
    G

    bundle :install, :artifice => "compact_index_redirects"
    expect(out).to match(/Too many redirects/)
  end

  context "when --full-index is specified" do
    it "should use the modern index for install" do
      gemfile <<-G
        source "#{source_uri}"
        gem "rack"
      G

      bundle "install --full-index", :artifice => "compact_index"
      expect(out).to include("Fetching source index from #{source_uri}")
      expect(the_bundle).to include_gems "rack 1.0.0"
    end

    it "should use the modern index for update" do
      gemfile <<-G
        source "#{source_uri}"
        gem "rack"
      G

      bundle "update --full-index", :artifice => "compact_index"
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

    bundle! :install, :artifice => "compact_index_extra"
    expect(the_bundle).to include_gems "back_deps 1.0"
  end

  it "fetches gem versions even when those gems are already installed" do
    gemfile <<-G
      source "#{source_uri}"
      gem "rack", "1.0.0"
    G
    bundle! :install, :artifice => "compact_index_extra_api"
    expect(the_bundle).to include_gems "rack 1.0.0"

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
    bundle! :install, :artifice => "compact_index_extra_api"
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

    bundle! :install, :artifice => "compact_index_extra_api"

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

    bundle! :install, :artifice => "compact_index_extra"

    expect(out).to include("Fetching gem metadata from http://localgemserver.test/")
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

    bundle! :install, :artifice => "compact_index_extra_missing"
    expect(the_bundle).to include_gems "back_deps 1.0"
  end

  it "uses the endpoint if all sources support it" do
    gemfile <<-G
      source "#{source_uri}"

      gem 'foo'
    G

    bundle! :install, :artifice => "compact_index_api_missing"
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

    bundle! :install, :artifice => "compact_index_extra"

    bundle "install --deployment", :artifice => "compact_index_extra"
    expect(the_bundle).to include_gems "back_deps 1.0"
  end

  it "does not refetch if the only unmet dependency is bundler" do
    gemfile <<-G
      source "#{source_uri}"

      gem "bundler_dep"
    G

    bundle! :install, :artifice => "compact_index"
    expect(out).to include("Fetching gem metadata from #{source_uri}")
  end

  it "should install when EndpointSpecification has a bin dir owned by root", :sudo => true do
    sudo "mkdir -p #{system_gem_path("bin")}"
    sudo "chown -R root #{system_gem_path("bin")}"

    gemfile <<-G
      source "#{source_uri}"
      gem "rails"
    G
    bundle! :install, :artifice => "compact_index"
    expect(the_bundle).to include_gems "rails 2.3.2"
  end

  it "installs the binstubs" do
    gemfile <<-G
      source "#{source_uri}"
      gem "rack"
    G

    bundle "install --binstubs", :artifice => "compact_index"

    gembin "rackup"
    expect(out).to eq("1.0.0")
  end

  it "installs the bins when using --path and uses autoclean" do
    gemfile <<-G
      source "#{source_uri}"
      gem "rack"
    G

    bundle "install --path vendor/bundle", :artifice => "compact_index"

    expect(vendored_gems("bin/rackup")).to exist
  end

  it "installs the bins when using --path and uses bundle clean" do
    gemfile <<-G
      source "#{source_uri}"
      gem "rack"
    G

    bundle "install --path vendor/bundle --no-clean", :artifice => "compact_index"

    expect(vendored_gems("bin/rackup")).to exist
  end

  it "prints post_install_messages" do
    gemfile <<-G
      source "#{source_uri}"
      gem 'rack-obama'
    G

    bundle! :install, :artifice => "compact_index"
    expect(out).to include("Post-install message from rack:")
  end

  it "should display the post install message for a dependency" do
    gemfile <<-G
      source "#{source_uri}"
      gem 'rack_middleware'
    G

    bundle! :install, :artifice => "compact_index"
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

      bundle! :install, :artifice => "compact_index_basic_authentication"
      expect(out).not_to include("#{user}:#{password}")
      expect(the_bundle).to include_gems "rack 1.0.0"
    end

    it "strips http basic authentication creds for modern index" do
      gemfile <<-G
        source "#{basic_auth_source_uri}"
        gem "rack"
      G

      bundle! :install, :artifice => "endopint_marshal_fail_basic_authentication"
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

      bundle! :install, :artifice => "compact_index_basic_authentication"
      expect(out).to include("Warning: the gem 'rack' was found in multiple sources.")
      expect(out).not_to include("#{user}:#{password}")
      expect(the_bundle).to include_gems "rack 1.0.0"
    end

    it "does not pass the user / password to different hosts on redirect" do
      gemfile <<-G
        source "#{basic_auth_source_uri}"
        gem "rack"
      G

      bundle! :install, :artifice => "compact_index_creds_diff_host"
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

        bundle! :install, :artifice => "compact_index_strict_basic_authentication"

        expect(out).to include("Fetching gem metadata from #{source_uri}")
        expect(the_bundle).to include_gems "rack 1.0.0"
      end

      it "reads authentication details by full url from bundle config" do
        # The trailing slash is necessary here; Fetcher canonicalizes the URI.
        bundle "config #{source_uri}/ #{user}:#{password}"

        bundle! :install, :artifice => "compact_index_strict_basic_authentication"

        expect(out).to include("Fetching gem metadata from #{source_uri}")
        expect(the_bundle).to include_gems "rack 1.0.0"
      end

      it "should use the API" do
        bundle "config #{source_hostname} #{user}:#{password}"
        bundle! :install, :artifice => "compact_index_strict_basic_authentication"
        expect(out).to include("Fetching gem metadata from #{source_uri}")
        expect(the_bundle).to include_gems "rack 1.0.0"
      end

      it "prefers auth supplied in the source uri" do
        gemfile <<-G
          source "#{basic_auth_source_uri}"
          gem "rack"
        G

        bundle "config #{source_hostname} otheruser:wrong"

        bundle! :install, :artifice => "compact_index_strict_basic_authentication"
        expect(the_bundle).to include_gems "rack 1.0.0"
      end

      it "shows instructions if auth is not provided for the source" do
        bundle :install, :artifice => "compact_index_strict_basic_authentication"
        expect(out).to include("bundle config #{source_hostname} username:password")
      end

      it "fails if authentication has already been provided, but failed" do
        bundle "config #{source_hostname} #{user}:wrong"

        bundle :install, :artifice => "compact_index_strict_basic_authentication"
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

        bundle! :install, :artifice => "compact_index_basic_authentication"
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

      bundle! :install, :artifice => "compact_index_forbidden"
    end
  end

  it "performs partial update with a non-empty range" do
    gemfile <<-G
      source "#{source_uri}"
      gem 'rack', '0.9.1'
    G

    # Initial install creates the cached versions file
    bundle! :install, :artifice => "compact_index"

    # Update the Gemfile so we can check subsequent install was successful
    gemfile <<-G
      source "#{source_uri}"
      gem 'rack', '1.0.0'
    G

    # Second install should make only a partial request to /versions
    bundle! :install, :artifice => "compact_index_partial_update"

    expect(the_bundle).to include_gems "rack 1.0.0"
  end

  it "performs partial update while local cache is updated by another process" do
    gemfile <<-G
      source "#{source_uri}"
      gem 'rack'
    G

    # Create an empty file to trigger a partial download
    versions = File.join(Bundler.rubygems.user_home, ".bundle", "cache", "compact_index",
      "localgemserver.test.80.dd34752a738ee965a2a4298dc16db6c5", "versions")
    FileUtils.mkdir_p(File.dirname(versions))
    FileUtils.touch(versions)

    bundle! :install, :artifice => "compact_index_concurrent_download"

    expect(File.read(versions)).to start_with("created_at")
    expect(the_bundle).to include_gems "rack 1.0.0"
  end

  it "fails gracefully when the source URI has an invalid scheme" do
    install_gemfile <<-G
      source "htps://rubygems.org"
      gem "rack"
    G
    expect(exitstatus).to eq(15) if exitstatus
    expect(out).to end_with(<<-E.strip)
      The request uri `htps://index.rubygems.org/versions` has an invalid scheme (`htps`). Did you mean `http` or `https`?
    E
  end

  describe "checksum validation", :rubygems => ">= 2.3.0" do
    it "raises when the checksum does not match" do
      install_gemfile <<-G, :artifice => "compact_index_wrong_gem_checksum"
        source "#{source_uri}"
        gem "rack"
      G

      expect(exitstatus).to eq(19) if exitstatus
      expect(out).
        to  include("Bundler cannot continue installing rack (1.0.0).").
        and include("The checksum for the downloaded `rack-1.0.0.gem` does not match the checksum given by the server.").
        and include("This means the contents of the downloaded gem is different from what was uploaded to the server, and could be a potential security issue.").
        and include("To resolve this issue:").
        and include("1. delete the downloaded gem located at: `#{system_gem_path}/gems/rack-1.0.0/rack-1.0.0.gem`").
        and include("2. run `bundle install`").
        and include("If you wish to continue installing the downloaded gem, and are certain it does not pose a security issue despite the mismatching checksum, do the following:").
        and include("1. run `bundle config disable_checksum_validation true` to turn off checksum verification").
        and include("2. run `bundle install`").
        and match(/\(More info: The expected SHA256 checksum was "#{"ab" * 22}", but the checksum for the downloaded gem was ".+?"\.\)/)
    end

    it "raises when the checksum is the wrong length" do
      install_gemfile <<-G, :artifice => "compact_index_wrong_gem_checksum", :env => { "BUNDLER_SPEC_RACK_CHECKSUM" => "checksum!" }
        source "#{source_uri}"
        gem "rack"
      G
      expect(exitstatus).to eq(5) if exitstatus
      expect(out).to include("The given checksum for rack-1.0.0 (\"checksum!\") is not a valid SHA256 hexdigest nor base64digest")
    end

    it "does not raise when disable_checksum_validation is set" do
      bundle! "config disable_checksum_validation true"
      install_gemfile! <<-G, :artifice => "compact_index_wrong_gem_checksum"
        source "#{source_uri}"
        gem "rack"
      G
    end
  end

  it "works when cache dir is world-writable" do
    install_gemfile! <<-G, :artifice => "compact_index"
      File.umask(0000)
      source "#{source_uri}"
      gem "rack"
    G
  end

  it "doesn't explode when the API dependencies are wrong" do
    install_gemfile <<-G, :artifice => "compact_index_wrong_dependencies", :env => { "DEBUG" => "true" }
      source "#{source_uri}"
      gem "rails"
    G
    deps = [Gem::Dependency.new("rake", "= 10.0.2"),
            Gem::Dependency.new("actionpack", "= 2.3.2"),
            Gem::Dependency.new("activerecord", "= 2.3.2"),
            Gem::Dependency.new("actionmailer", "= 2.3.2"),
            Gem::Dependency.new("activeresource", "= 2.3.2")]
    expect(out).to include(<<-E.strip).and include("rails-2.3.2 from rubygems remote at #{source_uri}/ has either corrupted API or lockfile dependencies")
Bundler::APIResponseMismatchError: Downloading rails-2.3.2 revealed dependencies not in the API or the lockfile (#{deps.map(&:to_s).join(", ")}).
Either installing with `--full-index` or running `bundle update rails` should fix the problem.
    E
  end

  it "does not duplicate specs in the lockfile when updating and a dependency is not installed" do
    install_gemfile! <<-G, :artifice => "compact_index"
      source "#{source_uri}" do
        gem "rails"
        gem "activemerchant"
      end
    G
    gem_command! :uninstall, "activemerchant"
    bundle! "update rails", :artifice => "compact_index"
    expect(lockfile.scan(/activemerchant \(/).size).to eq(1)
  end
end
