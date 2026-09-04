# frozen_string_literal: true

require "bundler/installer/parallel_installer"
require "bundler/rubygems_gem_installer"
require "rubygems/remote_fetcher"
require "bundler"

RSpec.describe Bundler::ParallelInstaller do
  describe "priority queue" do
    before do
      require "support/artifice/compact_index"
      Artifice.activate_with(CompactIndexAPI)

      @previous_client = Gem::Request::ConnectionPools.client
      Gem::Request::ConnectionPools.client = Gem::Net::HTTP
      Gem::RemoteFetcher.fetcher.close_all

      build_repo2 do
        build_gem "gem_with_extension", &:add_c_extension
        build_gem "gem_without_extension"
      end

      gemfile <<~G
        source "https://gem.repo2"

        gem "gem_with_extension"
        gem "gem_without_extension"
      G
      lockfile <<~L
        GEM
          remote: https://gem.repo2/
          specs:
            gem_with_extension (1.0)
            gem_without_extension (1.0)

        DEPENDENCIES
          gem_with_extension
          gem_without_extension
      L

      @old_ui = Bundler.ui
      Bundler.ui = Bundler::UI::Silent.new
    end

    after do
      Bundler.ui = @old_ui
      Gem::Request::ConnectionPools.client = @previous_client
      Artifice.deactivate
    end

    let(:definition) do
      allow(Bundler).to receive(:root) { bundled_app }

      definition = Bundler::Definition.build(bundled_app.join("Gemfile"), bundled_app.join("Gemfile.lock"), false)
      definition.tap(&:setup_domain!)
    end
    let(:installer) { Bundler::Installer.new(bundled_app, definition) }

    it "prioritizes native extensions for installation" do
      parallel_installer = Bundler::ParallelInstaller.new(installer, definition.specs, 2, false, true)
      download_worker_pool = parallel_installer.send(:download_worker_pool)
      install_worker_pool = parallel_installer.send(:worker_pool)

      expect(download_worker_pool).to receive(:enq).exactly(3).times.and_call_original
      expect(install_worker_pool).to receive(:enq).exactly(3).times.and_wrap_original do |original_enq, spec, opts|
        if spec.name == "gem_with_extension"
          expect(opts).to eq({ priority: true })
        else
          expect(opts).to eq({ priority: false })
        end

        original_enq.call(spec, **opts)
      end

      parallel_installer.call
    end
  end

  describe "worker pools" do
    it "uses separate worker pools with the configured size" do
      parallel_installer = described_class.new(nil, [], 2, false, false)

      download_worker_pool = parallel_installer.send(:download_worker_pool)
      install_worker_pool = parallel_installer.send(:worker_pool)

      expect(download_worker_pool).not_to equal(install_worker_pool)
      expect(download_worker_pool.instance_variable_get(:@size)).to eq(2)
      expect(install_worker_pool.instance_variable_get(:@size)).to eq(2)
    ensure
      install_worker_pool&.stop
      download_worker_pool&.stop
    end

    it "restores the previous interrupt handler after shutting down" do
      parallel_installer = described_class.new(nil, [], 2, false, false)
      download_worker_pool = parallel_installer.send(:download_worker_pool)
      install_worker_pool = parallel_installer.send(:worker_pool)

      previous_handler = Signal.trap("INT", "IGNORE")
      custom_handler = proc {}
      Signal.trap("INT", custom_handler)

      download_worker_pool.send(:create_threads)
      install_worker_pool.send(:create_threads)

      parallel_installer.call

      restored_handler = Signal.trap("INT", previous_handler)
      expect(restored_handler).to equal(custom_handler)
    ensure
      Signal.trap("INT", previous_handler) if previous_handler
    end
  end

  describe "connect to make jobserver" do
    before do
      unless Gem::Installer.private_method_defined?(:build_jobs)
        skip "This example is runnable when RubyGems::Installer implements `build_jobs`"
      end

      # The make jobserver is a GNU make feature. On Windows extensions are built
      # with nmake, which has no `-j` jobserver, so the per-gem slot count never
      # appears in the build output.
      skip "The make jobserver is not available on Windows (nmake)" if mswin?

      # When run under a parent make that already passes `-j` (e.g. ruby/ruby's
      # `make test-bundler-parallel`), RubyGems' extension builder sees the
      # inherited MAKEFLAGS as "jobs already requested" and skips appending its
      # own `-jN`. That makes the per-gem slot count unobservable, so these
      # assertions can never hold. Skip rather than fail in that environment.
      if ENV["MAKEFLAGS"]&.match?(/-j\d*(\s|\Z)/)
        skip "This example does not work under a parent make jobserver"
      end

      require "support/artifice/compact_index"
      Artifice.activate_with(CompactIndexAPI)

      @previous_client = Gem::Request::ConnectionPools.client
      Gem::Request::ConnectionPools.client = Gem::Net::HTTP
      Gem::RemoteFetcher.fetcher.close_all

      build_repo2 do
        build_gem "one", &:add_c_extension
        build_gem "two", &:add_c_extension
      end

      gemfile <<~G
        source "https://gem.repo2"

        gem "one"
        gem "two"
      G
      lockfile <<~L
        GEM
          remote: https://gem.repo2/
          specs:
            one (1.0)
            two (1.0)

        DEPENDENCIES
          one
          two
      L

      @old_ui = Bundler.ui
      Bundler.ui = Bundler::UI::Silent.new
    end

    # The `before` hook can `skip` before it saves anything, so only restore
    # what was actually captured. Otherwise every skipped example clobbers the
    # globals with nil.
    after do
      Bundler.ui = @old_ui if @old_ui
      Gem::Request::ConnectionPools.client = @previous_client if @previous_client
      Artifice.deactivate
    end

    let(:definition) do
      allow(Bundler).to receive(:root) { bundled_app }

      definition = Bundler::Definition.build(bundled_app.join("Gemfile"), bundled_app.join("Gemfile.lock"), false)
      definition.tap(&:setup_domain!)
    end
    let(:installer) { Bundler::Installer.new(bundled_app, definition) }
    let(:gem_one) { definition.specs.find {|spec| spec.name == "one" } }
    let(:gem_two) { definition.specs.find {|spec| spec.name == "two" } }

    it "takes all available slots" do
      redefine_build_jobs do
        Bundler::ParallelInstaller.call(installer, definition.specs, 5, false, true)
      end

      # Take 3 slots out of the 5 available.
      expect(File.read(File.join(gem_one.extension_dir, "gem_make.out"))).to include("make -j3")
      # Take the remaining 2 slots.
      expect(File.read(File.join(gem_two.extension_dir, "gem_make.out"))).to include("make -j2")
    end

    it "fallback to non parallel when no slots are available" do
      redefine_build_jobs do
        Bundler::ParallelInstaller.call(installer, definition.specs, 3, false, true)
      end

      # Take 3 slots out of the 3 available.
      expect(File.read(File.join(gem_one.extension_dir, "gem_make.out"))).to include("make -j3")
      # Fallback to one slot (non parallel).
      expect(File.read(File.join(gem_two.extension_dir, "gem_make.out"))).to_not include("make -j")
    end

    it "uses one jobs when installing serially" do
      Bundler.settings.temporary(jobs: 1) do
        Bundler::ParallelInstaller.call(installer, definition.specs, 1, false, true)
      end

      expect(File.read(File.join(gem_one.extension_dir, "gem_make.out"))).to_not include("make -j")
      expect(File.read(File.join(gem_two.extension_dir, "gem_make.out"))).to_not include("make -j")
    end

    it "release the job slots" do
      build_repo2 do
        build_gem "one", &:add_c_extension
        build_gem "two" do |spec|
          spec.add_c_extension
          spec.add_dependency(:one) # ParallelInstaller will wait for `one` to be fully installed.
        end
      end

      Bundler::ParallelInstaller.call(installer, definition.specs, 3, false, true)

      # Take 3 slots out of the 3 available.
      expect(File.read(File.join(gem_one.extension_dir, "gem_make.out"))).to include("make -j3")
      # Take 3 slots that were released.
      expect(File.read(File.join(gem_two.extension_dir, "gem_make.out"))).to include("make -j3")
    end

    def redefine_build_jobs
      old_method = Bundler::RubyGemsGemInstaller.instance_method(:build_jobs)
      Bundler::RubyGemsGemInstaller.remove_method(:build_jobs)

      # Rendezvous so that "one" grabs its slots first and keeps holding them
      # until "two" has grabbed the rest. Blocking on a queue avoids the
      # busy-wait and makes the ordering deterministic.
      one_acquired = Thread::Queue.new
      two_acquired = Thread::Queue.new

      Bundler::RubyGemsGemInstaller.define_method(:build_jobs) do
        if spec.name == "one"
          value = old_method.bind(self).call
          one_acquired << true
          two_acquired.pop
        elsif spec.name == "two"
          one_acquired.pop
          value = old_method.bind(self).call
          two_acquired << true
        end

        value
      end

      yield
    ensure
      Bundler::RubyGemsGemInstaller.remove_method(:build_jobs)
      Bundler::RubyGemsGemInstaller.define_method(:build_jobs, old_method)
    end
  end

  describe "require tree in error reports" do
    # require_tree_for_spec runs while reporting an install error. When no
    # Gemfile can be located, default_gemfile raises GemfileNotFound, which
    # would mask the original install error entirely.
    it "falls back to a generic header when no Gemfile can be located" do
      parallel_installer = Bundler::ParallelInstaller.new(nil, [], 1, false, false)

      spec = double("spec", name: "mygem", version: Gem::Version.new("1.0"))
      spec_set = double("spec_set", what_required: [spec])
      parallel_installer.instance_variable_set(:@spec_set, spec_set)

      allow(Bundler::SharedHelpers).to receive(:default_gemfile).
        and_raise(Bundler::GemfileNotFound, "Could not locate Gemfile")

      tree = parallel_installer.send(:require_tree_for_spec, spec)
      expect(tree).to start_with("In Gemfile:\n")
      expect(tree).to include("mygem")
    end
  end

  describe "make jobserver with nmake" do
    # nmake reads MAKEFLAGS from the environment and treats its contents as
    # bare option letters, so a GNU make `--jobserver-auth` aborts the build
    # with `fatal error U1065: invalid option '-'`. The jobserver must be
    # skipped when nmake is the make program.
    it "leaves MAKEFLAGS untouched" do
      parallel_installer = Bundler::ParallelInstaller.new(nil, [], 5, false, false)

      makeflags_before = ENV["MAKEFLAGS"]
      makeflags_during = :not_yielded

      old_make = ENV["MAKE"]
      ENV["MAKE"] = "nmake"
      begin
        parallel_installer.send(:with_jobserver) do
          makeflags_during = ENV["MAKEFLAGS"]
        end
      ensure
        ENV["MAKE"] = old_make
      end

      expect(makeflags_during).to eq(makeflags_before)
    end
  end

  describe "make jobserver on BSD" do
    # BSD make (the default `make` on FreeBSD) can't parse the GNU
    # `--jobserver-auth` and aborts every native extension build, so the
    # jobserver must be skipped there.
    it "leaves MAKEFLAGS untouched" do
      parallel_installer = Bundler::ParallelInstaller.new(nil, [], 5, false, false)

      makeflags_before = ENV["MAKEFLAGS"]
      makeflags_during = :not_yielded

      old_make = ENV["MAKE"]
      ENV.delete("MAKE")
      allow(Gem).to receive(:freebsd_platform?).and_return(true)
      begin
        parallel_installer.send(:with_jobserver) do
          makeflags_during = ENV["MAKEFLAGS"]
        end
      ensure
        ENV["MAKE"] = old_make
      end

      expect(makeflags_during).to eq(makeflags_before)
    end

    # A BSD user who opts into gmake gets a make that understands the
    # jobserver, so it should still be set up.
    it "sets up the jobserver when gmake is used" do
      parallel_installer = Bundler::ParallelInstaller.new(nil, [], 5, false, false)

      makeflags_during = :not_yielded

      old_make = ENV["MAKE"]
      ENV["MAKE"] = "gmake"
      allow(Gem).to receive(:freebsd_platform?).and_return(true)
      begin
        parallel_installer.send(:with_jobserver) do
          makeflags_during = ENV["MAKEFLAGS"]
        end
      ensure
        ENV["MAKE"] = old_make
      end

      expect(makeflags_during).to include("--jobserver-auth=")
    end
  end
end
