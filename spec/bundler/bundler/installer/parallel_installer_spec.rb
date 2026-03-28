# frozen_string_literal: true

require "bundler/installer/parallel_installer"
require "bundler/rubygems_gem_installer"
require "rubygems/remote_fetcher"
require "bundler"

RSpec.describe Bundler::ParallelInstaller do
  describe "priority queue" do
    before do
      require "support/artifice/compact_index"

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

    it "queues native extensions in priority" do
      parallel_installer = Bundler::ParallelInstaller.new(installer, definition.specs, 2, false, true)
      worker_pool = parallel_installer.send(:worker_pool)
      expected = 6 # Enqueue to download bundler and the 2 gems. Enqueue to install Bundler and the 2 gems.

      expect(worker_pool).to receive(:enq).exactly(expected).times.and_wrap_original do |original_enq, spec, opts|
        unless opts.nil? # Enqueued for download, no priority
          if spec.name == "gem_with_extension"
            expect(opts).to eq({ priority: true })
          else
            expect(opts).to eq({ priority: false })
          end
        end

        opts ||= {}
        original_enq.call(spec, **opts)
      end

      parallel_installer.call
    end
  end
end
