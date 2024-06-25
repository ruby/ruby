# frozen_string_literal: true

RSpec.describe "compact index api" do
  let(:source_hostname) { "localgemserver.test" }
  let(:source_uri) { "http://#{source_hostname}" }

  it "should use the API" do
    gemfile <<-G
      source "#{source_uri}"
      gem "rack"
    G

    bundle :install, artifice: "compact_index"
    expect(out).to include("Fetching gem metadata from #{source_uri}")
    expect(the_bundle).to include_gems "rack 1.0.0"
  end

  it "has a debug mode" do
    gemfile <<-G
      source "#{source_uri}"
      gem "rack"
    G

    bundle :install, artifice: "compact_index", env: { "DEBUG_COMPACT_INDEX" => "true" }
    expect(out).to include("Fetching gem metadata from #{source_uri}")
    expect(err).to include("[Bundler::CompactIndexClient] available?")
    expect(err).to include("[Bundler::CompactIndexClient] fetching versions")
    expect(err).to include("[Bundler::CompactIndexClient] info(rack)")
    expect(err).to include("[Bundler::CompactIndexClient] fetching info/rack")
    expect(the_bundle).to include_gems "rack 1.0.0"
  end

  it "should URI encode gem names" do
    gemfile <<-G
      source "#{source_uri}"
      gem " sinatra"
    G

    bundle :install, artifice: "compact_index", raise_on_error: false
    expect(err).to include("' sinatra' is not a valid gem name because it contains whitespace.")
  end

  it "should handle nested dependencies" do
    gemfile <<-G
      source "#{source_uri}"
      gem "rails"
    G

    bundle :install, artifice: "compact_index"
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
    build_repo4(build_compact_index: false) do
      build_gem "rack", "1.0" do |s|
        s.add_runtime_dependency("Rack", "0.1")
      end
      build_gem "Rack", "0.1"
    end

    install_gemfile <<-G, artifice: "compact_index", env: { "BUNDLER_SPEC_GEM_REPO" => gem_repo4.to_s }
      source "#{source_uri}"
      gem "rack", "1.0"
      gem "Rack", "0.1"
    G

    # can't use `include_gems` here since the `require` will conflict on a
    # case-insensitive FS
    run "Bundler.require; puts Gem.loaded_specs.values_at('rack', 'Rack').map(&:full_name)"
    expect(out).to eq("rack-1.0\nRack-0.1")
  end

  it "should handle multiple gem dependencies on the same gem" do
    gemfile <<-G
      source "#{source_uri}"
      gem "net-sftp"
    G

    bundle :install, artifice: "compact_index"
    expect(the_bundle).to include_gems "net-sftp 1.1.1"
  end

  it "should use the endpoint when using deployment mode" do
    gemfile <<-G
      source "#{source_uri}"
      gem "rack"
    G
    bundle :install, artifice: "compact_index"

    bundle "config set --local deployment true"
    bundle "config set --local path vendor/bundle"
    bundle :install, artifice: "compact_index"
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

    bundle :install, artifice: "compact_index"

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

    bundle :install, artifice: "compact_index"

    bundle "config set --local deployment true"
    bundle :install, artifice: "compact_index"

    expect(the_bundle).to include_gems("rails 2.3.2")
  end

  it "doesn't fail if you only have a git gem with no deps when using deployment mode" do
    build_git "foo"
    gemfile <<-G
      source "#{source_uri}"
      gem 'foo', :git => "#{file_uri_for(lib_path("foo-1.0"))}"
    G

    bundle "install", artifice: "compact_index"
    bundle "config set --local deployment true"
    bundle :install, artifice: "compact_index"

    expect(the_bundle).to include_gems("foo 1.0")
  end

  it "falls back when the API URL returns 403 Forbidden" do
    gemfile <<-G
      source "#{source_uri}"
      gem "rack"
    G

    bundle :install, verbose: true, artifice: "compact_index_forbidden"
    expect(out).to include("Fetching gem metadata from #{source_uri}")
    expect(the_bundle).to include_gems "rack 1.0.0"
  end

  it "falls back when the versions endpoint has a checksum mismatch" do
    gemfile <<-G
      source "#{source_uri}"
      gem "rack"
    G

    bundle :install, verbose: true, artifice: "compact_index_checksum_mismatch"
    expect(out).to include("Fetching gem metadata from #{source_uri}")
    expect(out).to include("The checksum of /versions does not match the checksum provided by the server!")
    expect(out).to include('Calculated checksums {"sha-256"=>"8KfZiM/fszVkqhP/m5s9lvE6M9xKu4I1bU4Izddp5Ms="} did not match expected {"sha-256"=>"ungWv48Bz+pBQUDeXa4iI7ADYaOWF3qctBD/YfIAFa0="}')
    expect(the_bundle).to include_gems "rack 1.0.0"
  end

  it "shows proper path when permission errors happen", :permissions do
    gemfile <<-G
      source "#{source_uri}"
      gem "rack"
    G

    versions = Pathname.new(Bundler.rubygems.user_home).join(
      ".bundle", "cache", "compact_index",
      "localgemserver.test.80.dd34752a738ee965a2a4298dc16db6c5", "versions"
    )
    versions.dirname.mkpath
    versions.write("created_at")
    FileUtils.chmod("-r", versions)

    bundle :install, artifice: "compact_index", raise_on_error: false

    expect(err).to include(
      "There was an error while trying to read from `#{versions}`. It is likely that you need to grant read permissions for that path."
    )
  end

  it "falls back when the user's home directory does not exist or is not writable" do
    ENV["HOME"] = tmp("missing_home").to_s

    gemfile <<-G
      source "#{source_uri}"
      gem "rack"
    G

    bundle :install, artifice: "compact_index"
    expect(out).to include("Fetching gem metadata from #{source_uri}")
    expect(the_bundle).to include_gems "rack 1.0.0"
  end

  it "handles host redirects" do
    gemfile <<-G
      source "#{source_uri}"
      gem "rack"
    G

    bundle :install, artifice: "compact_index_host_redirect"
    expect(the_bundle).to include_gems "rack 1.0.0"
  end

  it "handles host redirects without Gem::Net::HTTP::Persistent" do
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

    bundle :install, artifice: "compact_index_host_redirect", requires: [lib_path("disable_net_http_persistent.rb")]
    expect(out).to_not match(/Too many redirects/)
    expect(the_bundle).to include_gems "rack 1.0.0"
  end

  it "times out when Bundler::Fetcher redirects too much" do
    gemfile <<-G
      source "#{source_uri}"
      gem "rack"
    G

    bundle :install, artifice: "compact_index_redirects", raise_on_error: false
    expect(err).to match(/Too many redirects/)
  end

  context "when --full-index is specified" do
    it "should use the modern index for install" do
      gemfile <<-G
        source "#{source_uri}"
        gem "rack"
      G

      bundle "install --full-index", artifice: "compact_index"
      expect(out).to include("Fetching source index from #{source_uri}")
      expect(the_bundle).to include_gems "rack 1.0.0"
    end

    it "should use the modern index for update" do
      gemfile <<-G
        source "#{source_uri}"
        gem "rack"
      G

      bundle "update --full-index", artifice: "compact_index", all: true
      expect(out).to include("Fetching source index from #{source_uri}")
      expect(the_bundle).to include_gems "rack 1.0.0"
    end
  end

  it "does not double check for gems that are only installed locally" do
    build_repo2 do
      build_gem "net_a" do |s|
        s.add_dependency "net_b"
        s.add_dependency "net_build_extensions"
      end

      build_gem "net_b"

      build_gem "net_build_extensions" do |s|
        s.add_dependency "rake"
        s.extensions << "Rakefile"
        s.write "Rakefile", <<-RUBY
          task :default do
            path = File.expand_path("lib", __dir__)
            FileUtils.mkdir_p(path)
            File.open("\#{path}/net_build_extensions.rb", "w") do |f|
              f.puts "NET_BUILD_EXTENSIONS = 'YES'"
            end
          end
        RUBY
      end
    end

    system_gems %w[rack-1.0.0 thin-1.0 net_a-1.0], gem_repo: gem_repo2
    bundle "config set --local path.system true"
    ENV["BUNDLER_SPEC_ALL_REQUESTS"] = <<~EOS.strip
      #{source_uri}/versions
      #{source_uri}/info/rack
    EOS

    install_gemfile <<-G, artifice: "compact_index", verbose: true, env: { "BUNDLER_SPEC_GEM_REPO" => gem_repo2.to_s }
      source "#{source_uri}"
      gem "rack"
    G

    expect(last_command.stdboth).not_to include "Double checking"
  end

  it "fetches again when more dependencies are found in subsequent sources", bundler: "< 3" do
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

    bundle :install, artifice: "compact_index_extra"
    expect(the_bundle).to include_gems "back_deps 1.0", "foo 1.0"
  end

  it "fetches again when more dependencies are found in subsequent sources with source blocks" do
    build_repo2 do
      build_gem "back_deps" do |s|
        s.add_dependency "foo"
      end
      FileUtils.rm_rf Dir[gem_repo2("gems/foo-*.gem")]
    end

    install_gemfile <<-G, artifice: "compact_index_extra", verbose: true
      source "#{source_uri}"
      source "#{source_uri}/extra" do
        gem "back_deps"
      end
    G

    expect(the_bundle).to include_gems "back_deps 1.0", "foo 1.0"
  end

  it "fetches gem versions even when those gems are already installed" do
    gemfile <<-G
      source "#{source_uri}"
      gem "rack", "1.0.0"
    G
    bundle :install, artifice: "compact_index_extra_api"
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
    bundle :install, artifice: "compact_index_extra_api"
    expect(the_bundle).to include_gems "rack 1.2"
  end

  it "considers all possible versions of dependencies from all api gem sources", bundler: "< 3" do
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

    bundle :install, artifice: "compact_index_extra_api"

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

    bundle :install, artifice: "compact_index_extra"

    expect(out).to include("Fetching gem metadata from http://localgemserver.test/")
    expect(out).to include("Fetching source index from http://localgemserver.test/extra")
  end

  it "does not fetch every spec when doing back deps" do
    build_repo2 do
      build_gem "back_deps" do |s|
        s.add_dependency "foo"
      end
      build_gem "missing"

      FileUtils.rm_rf Dir[gem_repo2("gems/foo-*.gem")]
    end

    install_gemfile <<-G, artifice: "compact_index_extra_missing"
      source "#{source_uri}"
      source "#{source_uri}/extra" do
        gem "back_deps"
      end
    G

    expect(the_bundle).to include_gems "back_deps 1.0"
  end

  it "does not fetch every spec when doing back deps & everything is the compact index" do
    build_repo4 do
      build_gem "back_deps" do |s|
        s.add_dependency "foo"
      end
      build_gem "missing"

      FileUtils.rm_rf Dir[gem_repo4("gems/foo-*.gem")]
    end

    install_gemfile <<-G, artifice: "compact_index_extra_api_missing"
      source "#{source_uri}"
      source "#{source_uri}/extra" do
        gem "back_deps"
      end
    G

    expect(the_bundle).to include_gem "back_deps 1.0"
  end

  it "uses the endpoint if all sources support it" do
    gemfile <<-G
      source "#{source_uri}"

      gem 'foo'
    G

    bundle :install, artifice: "compact_index_api_missing"
    expect(the_bundle).to include_gems "foo 1.0"
  end

  it "fetches again when more dependencies are found in subsequent sources using deployment mode", bundler: "< 3" do
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

    bundle :install, artifice: "compact_index_extra"
    bundle "config --set local deployment true"
    bundle :install, artifice: "compact_index_extra"
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

    bundle :install, artifice: "compact_index_extra"
    bundle "config set --local deployment true"
    bundle :install, artifice: "compact_index_extra"
    expect(the_bundle).to include_gems "back_deps 1.0"
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

    bundle :install, artifice: "compact_index", env: { "BUNDLER_SPEC_GEM_REPO" => gem_repo2.to_s }
    expect(out).to include("Fetching gem metadata from #{source_uri}")
  end

  it "installs the binstubs", bundler: "< 3" do
    gemfile <<-G
      source "#{source_uri}"
      gem "rack"
    G

    bundle "install --binstubs", artifice: "compact_index"

    gembin "rackup"
    expect(out).to eq("1.0.0")
  end

  it "installs the bins when using --path and uses autoclean", bundler: "< 3" do
    gemfile <<-G
      source "#{source_uri}"
      gem "rack"
    G

    bundle "install --path vendor/bundle", artifice: "compact_index"

    expect(vendored_gems("bin/rackup")).to exist
  end

  it "installs the bins when using --path and uses bundle clean", bundler: "< 3" do
    gemfile <<-G
      source "#{source_uri}"
      gem "rack"
    G

    bundle "install --path vendor/bundle --no-clean", artifice: "compact_index"

    expect(vendored_gems("bin/rackup")).to exist
  end

  it "prints post_install_messages" do
    gemfile <<-G
      source "#{source_uri}"
      gem 'rack-obama'
    G

    bundle :install, artifice: "compact_index"
    expect(out).to include("Post-install message from rack:")
  end

  it "should display the post install message for a dependency" do
    gemfile <<-G
      source "#{source_uri}"
      gem 'rack_middleware'
    G

    bundle :install, artifice: "compact_index"
    expect(out).to include("Post-install message from rack:")
    expect(out).to include("Rack's post install message")
  end

  context "when using basic authentication" do
    let(:user)     { "user" }
    let(:password) { "pass" }
    let(:basic_auth_source_uri) do
      uri          = Gem::URI.parse(source_uri)
      uri.user     = user
      uri.password = password

      uri
    end

    it "passes basic authentication details and strips out creds" do
      gemfile <<-G
        source "#{basic_auth_source_uri}"
        gem "rack"
      G

      bundle :install, artifice: "compact_index_basic_authentication"
      expect(out).not_to include("#{user}:#{password}")
      expect(the_bundle).to include_gems "rack 1.0.0"
    end

    it "passes basic authentication details and strips out creds also in verbose mode" do
      gemfile <<-G
        source "#{basic_auth_source_uri}"
        gem "rack"
      G

      bundle :install, verbose: true, artifice: "compact_index_basic_authentication"
      expect(out).not_to include("#{user}:#{password}")
      expect(the_bundle).to include_gems "rack 1.0.0"
    end

    it "strips http basic auth creds when warning about ambiguous sources", bundler: "< 3" do
      gemfile <<-G
        source "#{basic_auth_source_uri}"
        source "#{file_uri_for(gem_repo1)}"
        gem "rack"
      G

      bundle :install, artifice: "compact_index_basic_authentication"
      expect(err).to include("Warning: the gem 'rack' was found in multiple sources.")
      expect(err).not_to include("#{user}:#{password}")
      expect(the_bundle).to include_gems "rack 1.0.0"
    end

    it "does not pass the user / password to different hosts on redirect" do
      gemfile <<-G
        source "#{basic_auth_source_uri}"
        gem "rack"
      G

      bundle :install, artifice: "compact_index_creds_diff_host"
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
        bundle "config set #{source_hostname} #{user}:#{password}"

        bundle :install, artifice: "compact_index_strict_basic_authentication"

        expect(out).to include("Fetching gem metadata from #{source_uri}")
        expect(the_bundle).to include_gems "rack 1.0.0"
      end

      it "reads authentication details by full url from bundle config" do
        # The trailing slash is necessary here; Fetcher canonicalizes the URI.
        bundle "config set #{source_uri}/ #{user}:#{password}"

        bundle :install, artifice: "compact_index_strict_basic_authentication"

        expect(out).to include("Fetching gem metadata from #{source_uri}")
        expect(the_bundle).to include_gems "rack 1.0.0"
      end

      it "should use the API" do
        bundle "config set #{source_hostname} #{user}:#{password}"
        bundle :install, artifice: "compact_index_strict_basic_authentication"
        expect(out).to include("Fetching gem metadata from #{source_uri}")
        expect(the_bundle).to include_gems "rack 1.0.0"
      end

      it "prefers auth supplied in the source uri" do
        gemfile <<-G
          source "#{basic_auth_source_uri}"
          gem "rack"
        G

        bundle "config set #{source_hostname} otheruser:wrong"

        bundle :install, artifice: "compact_index_strict_basic_authentication"
        expect(the_bundle).to include_gems "rack 1.0.0"
      end

      it "shows instructions if auth is not provided for the source" do
        bundle :install, artifice: "compact_index_strict_basic_authentication", raise_on_error: false
        expect(err).to include("bundle config set --global #{source_hostname} username:password")
      end

      it "fails if authentication has already been provided, but failed" do
        bundle "config set #{source_hostname} #{user}:wrong"

        bundle :install, artifice: "compact_index_strict_basic_authentication", raise_on_error: false
        expect(err).to include("Bad username or password")
      end

      it "does not fallback to old dependency API if bad authentication is provided" do
        bundle "config set #{source_hostname} #{user}:wrong"

        bundle :install, artifice: "compact_index_strict_basic_authentication", raise_on_error: false, verbose: true
        expect(err).to include("Bad username or password")
        expect(out).to include("HTTP 401 Unauthorized http://user@localgemserver.test/versions")
        expect(out).not_to include("HTTP 401 Unauthorized http://user@localgemserver.test/api/v1/dependencies")
      end
    end

    describe "with no password" do
      let(:password) { nil }

      it "passes basic authentication details" do
        gemfile <<-G
          source "#{basic_auth_source_uri}"
          gem "rack"
        G

        bundle :install, artifice: "compact_index_basic_authentication"
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

      bundle :install, env: { "RUBYOPT" => opt_add("-I#{bundled_app("broken_ssl")}", ENV["RUBYOPT"]) }, raise_on_error: false
      expect(err).to include("OpenSSL")
    end
  end

  context "when SSL certificate verification fails" do
    it "explains what happened" do
      # Install a monkeypatch that reproduces the effects of openssl raising
      # a certificate validation error when RubyGems tries to connect.
      gemfile <<-G
        class Gem::Net::HTTP
          def start
            raise OpenSSL::SSL::SSLError, "certificate verify failed"
          end
        end

        source "#{source_uri.gsub(/http/, "https")}"
        gem "rack"
      G

      bundle :install, raise_on_error: false
      expect(err).to match(/could not verify the SSL certificate/i)
    end
  end

  context ".gemrc with sources is present" do
    it "uses other sources declared in the Gemfile" do
      File.open(home(".gemrc"), "w") do |file|
        file.puts({ sources: ["https://rubygems.org"] }.to_yaml)
      end

      begin
        gemfile <<-G
          source "#{source_uri}"
          gem 'rack'
        G

        bundle :install, artifice: "compact_index_forbidden"
      ensure
        home(".gemrc").rmtree
      end
    end
  end

  it "performs update with etag not-modified" do
    versions_etag = Pathname.new(Bundler.rubygems.user_home).join(
      ".bundle", "cache", "compact_index",
      "localgemserver.test.80.dd34752a738ee965a2a4298dc16db6c5", "versions.etag"
    )
    expect(versions_etag.file?).to eq(false)

    gemfile <<-G
      source "#{source_uri}"
      gem 'rack', '0.9.1'
    G

    # Initial install creates the cached versions file and etag file
    bundle :install, artifice: "compact_index"

    expect(versions_etag.file?).to eq(true)
    previous_content = versions_etag.binread

    # Update the Gemfile so we can check subsequent install was successful
    gemfile <<-G
      source "#{source_uri}"
      gem 'rack', '1.0.0'
    G

    # Second install should match etag
    bundle :install, artifice: "compact_index_etag_match"

    expect(versions_etag.binread).to eq(previous_content)
    expect(the_bundle).to include_gems "rack 1.0.0"
  end

  it "performs full update when range is ignored" do
    gemfile <<-G
      source "#{source_uri}"
      gem 'rack', '0.9.1'
    G

    # Initial install creates the cached versions file and etag file
    bundle :install, artifice: "compact_index"

    gemfile <<-G
      source "#{source_uri}"
      gem 'rack', '1.0.0'
    G

    versions = Pathname.new(Bundler.rubygems.user_home).join(
      ".bundle", "cache", "compact_index",
      "localgemserver.test.80.dd34752a738ee965a2a4298dc16db6c5", "versions"
    )
    # Modify the cached file. The ranged request will be based on this but,
    # in this test, the range is ignored so this gets overwritten, allowing install.
    versions.write "ruining this file"

    bundle :install, artifice: "compact_index_range_ignored"

    expect(the_bundle).to include_gems "rack 1.0.0"
  end

  it "performs partial update with a non-empty range" do
    build_repo4 do
      build_gem "rack", "0.9.1"
    end

    # Initial install creates the cached versions file
    install_gemfile <<-G, artifice: "compact_index", env: { "BUNDLER_SPEC_GEM_REPO" => gem_repo4.to_s }
      source "#{source_uri}"
      gem 'rack', '0.9.1'
    G

    update_repo4 do
      build_gem "rack", "1.0.0"
    end

    install_gemfile <<-G, artifice: "compact_index_partial_update", env: { "BUNDLER_SPEC_GEM_REPO" => gem_repo4.to_s }
      source "#{source_uri}"
      gem 'rack', '1.0.0'
    G

    expect(the_bundle).to include_gems "rack 1.0.0"
  end

  it "performs partial update while local cache is updated by another process" do
    gemfile <<-G
      source "#{source_uri}"
      gem 'rack'
    G

    # Create a partial cache versions file
    versions = Pathname.new(Bundler.rubygems.user_home).join(
      ".bundle", "cache", "compact_index",
      "localgemserver.test.80.dd34752a738ee965a2a4298dc16db6c5", "versions"
    )
    versions.dirname.mkpath
    versions.write("created_at")

    bundle :install, artifice: "compact_index_concurrent_download"

    expect(versions.read).to start_with("created_at")
    expect(the_bundle).to include_gems "rack 1.0.0"
  end

  it "performs a partial update that fails digest check, then a full update" do
    build_repo4 do
      build_gem "rack", "0.9.1"
    end

    install_gemfile <<-G, artifice: "compact_index", env: { "BUNDLER_SPEC_GEM_REPO" => gem_repo4.to_s }
      source "#{source_uri}"
      gem 'rack', '0.9.1'
    G

    update_repo4 do
      build_gem "rack", "1.0.0"
    end

    install_gemfile <<-G, artifice: "compact_index_partial_update_bad_digest", env: { "BUNDLER_SPEC_GEM_REPO" => gem_repo4.to_s }
      source "#{source_uri}"
      gem 'rack', '1.0.0'
    G

    expect(the_bundle).to include_gems "rack 1.0.0"
  end

  it "performs full update if server endpoints serve partial content responses but don't have incremental content and provide no digest" do
    build_repo4 do
      build_gem "rack", "0.9.1"
    end

    install_gemfile <<-G, artifice: "compact_index", env: { "BUNDLER_SPEC_GEM_REPO" => gem_repo4.to_s }
      source "#{source_uri}"
      gem 'rack', '0.9.1'
    G

    update_repo4 do
      build_gem "rack", "1.0.0"
    end

    install_gemfile <<-G, artifice: "compact_index_partial_update_no_digest_not_incremental", env: { "BUNDLER_SPEC_GEM_REPO" => gem_repo4.to_s }
      source "#{source_uri}"
      gem 'rack', '1.0.0'
    G

    expect(the_bundle).to include_gems "rack 1.0.0"
  end

  it "performs full update of compact index info cache if range is not satisfiable" do
    gemfile <<-G
      source "#{source_uri}"
      gem 'rack', '0.9.1'
    G

    bundle :install, artifice: "compact_index"

    # We must remove the etag so that we don't ignore the range and get a 304 Not Modified.
    rake_info_etag_path = File.join(Bundler.rubygems.user_home, ".bundle", "cache", "compact_index",
      "localgemserver.test.80.dd34752a738ee965a2a4298dc16db6c5", "info-etags", "rack-11690b09f16021ff06a6857d784a1870")
    File.unlink(rake_info_etag_path) if File.exist?(rake_info_etag_path)

    rake_info_path = File.join(Bundler.rubygems.user_home, ".bundle", "cache", "compact_index",
      "localgemserver.test.80.dd34752a738ee965a2a4298dc16db6c5", "info", "rack")
    expected_rack_info_content = File.read(rake_info_path)

    # Modify the cache files to make the range not satisfiable
    File.open(rake_info_path, "a") {|f| f << "0.9.2 |checksum:c55b525b421fd833a93171ad3d7f04528ca8e87d99ac273f8933038942a5888c" }

    # Update the Gemfile so the next install does its normal things
    gemfile <<-G
      source "#{source_uri}"
      gem 'rack', '1.0.0'
    G

    # The cache files now being longer means the requested range is going to be not satisfiable
    # Bundler must end up requesting the whole file to fix things up.
    bundle :install, artifice: "compact_index_range_not_satisfiable"

    resulting_rack_info_content = File.read(rake_info_path)

    expect(resulting_rack_info_content).to eq(expected_rack_info_content)
  end

  it "fails gracefully when the source URI has an invalid scheme" do
    install_gemfile <<-G, raise_on_error: false
      source "htps://rubygems.org"
      gem "rack"
    G
    expect(exitstatus).to eq(15)
    expect(err).to end_with(<<-E.strip)
      The request uri `htps://index.rubygems.org/versions` has an invalid scheme (`htps`). Did you mean `http` or `https`?
    E
  end

  describe "checksum validation" do
    before do
      lockfile <<-L
        GEM
          remote: #{source_uri}
          specs:
            rack (1.0.0)

        PLATFORMS
          ruby

        DEPENDENCIES
        #{checksums_section}
        BUNDLED WITH
            #{Bundler::VERSION}
      L
    end

    it "handles checksums from the server in base64" do
      api_checksum = checksum_digest(gem_repo1, "rack", "1.0.0")
      rack_checksum = [[api_checksum].pack("H*")].pack("m0")
      install_gemfile <<-G, artifice: "compact_index", env: { "BUNDLER_SPEC_RACK_CHECKSUM" => rack_checksum }
        source "#{source_uri}"
        gem "rack"
      G

      expect(out).to include("Fetching gem metadata from #{source_uri}")
      expect(the_bundle).to include_gems("rack 1.0.0")
    end

    it "raises when the checksum does not match" do
      install_gemfile <<-G, artifice: "compact_index_wrong_gem_checksum", raise_on_error: false
        source "#{source_uri}"
        gem "rack"
      G

      gem_path = if Bundler.feature_flag.global_gem_cache?
        default_cache_path.dirname.join("cache", "gems", "localgemserver.test.80.dd34752a738ee965a2a4298dc16db6c5", "rack-1.0.0.gem")
      else
        default_cache_path.dirname.join("rack-1.0.0.gem")
      end

      expect(exitstatus).to eq(37)
      expect(err).to eq <<~E.strip
        Bundler found mismatched checksums. This is a potential security risk.
          rack (1.0.0) sha256=2222222222222222222222222222222222222222222222222222222222222222
            from the API at http://localgemserver.test/
          #{checksum_to_lock(gem_repo1, "rack", "1.0.0")}
            from the gem at #{gem_path}

        If you trust the API at http://localgemserver.test/, to resolve this issue you can:
          1. remove the gem at #{gem_path}
          2. run `bundle install`

        To ignore checksum security warnings, disable checksum validation with
          `bundle config set --local disable_checksum_validation true`
      E
    end

    it "raises when the checksum is the wrong length" do
      install_gemfile <<-G, artifice: "compact_index_wrong_gem_checksum", env: { "BUNDLER_SPEC_RACK_CHECKSUM" => "checksum!", "DEBUG" => "1" }, verbose: true, raise_on_error: false
        source "#{source_uri}"
        gem "rack"
      G
      expect(exitstatus).to eq(14)
      expect(err).to include('Invalid checksum for rack-0.9.1: "checksum!" is not a valid SHA256 hex or base64 digest')
    end

    it "does not raise when disable_checksum_validation is set" do
      bundle "config set disable_checksum_validation true"
      install_gemfile <<-G, artifice: "compact_index_wrong_gem_checksum"
        source "#{source_uri}"
        gem "rack"
      G
    end
  end

  it "works when cache dir is world-writable" do
    install_gemfile <<-G, artifice: "compact_index"
      File.umask(0000)
      source "#{source_uri}"
      gem "rack"
    G
  end

  it "doesn't explode when the API dependencies are wrong" do
    install_gemfile <<-G, artifice: "compact_index_wrong_dependencies", env: { "DEBUG" => "true" }, raise_on_error: false
      source "#{source_uri}"
      gem "rails"
    G
    deps = [Gem::Dependency.new("rake", "= #{rake_version}"),
            Gem::Dependency.new("actionpack", "= 2.3.2"),
            Gem::Dependency.new("activerecord", "= 2.3.2"),
            Gem::Dependency.new("actionmailer", "= 2.3.2"),
            Gem::Dependency.new("activeresource", "= 2.3.2")]
    expect(out).to include("rails-2.3.2 from rubygems remote at #{source_uri}/ has either corrupted API or lockfile dependencies")
    expect(err).to include(<<-E.strip)
Bundler::APIResponseMismatchError: Downloading rails-2.3.2 revealed dependencies not in the API or the lockfile (#{deps.map(&:to_s).join(", ")}).
Running `bundle update rails` should fix the problem.
    E
  end

  it "does not duplicate specs in the lockfile when updating and a dependency is not installed" do
    install_gemfile <<-G, artifice: "compact_index"
      source "#{file_uri_for(gem_repo1)}"
      source "#{source_uri}" do
        gem "rails"
        gem "activemerchant"
      end
    G
    gem_command "uninstall activemerchant"
    bundle "update rails", artifice: "compact_index"
    count = lockfile.match?("CHECKSUMS") ? 2 : 1 # Once in the specs, and once in CHECKSUMS
    expect(lockfile.scan(/activemerchant \(/).size).to eq(count)
  end
end
