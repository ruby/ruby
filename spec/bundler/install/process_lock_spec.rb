# frozen_string_literal: true

RSpec.describe "process lock spec" do
  describe "when an install operation is already holding a process lock" do
    before { FileUtils.mkdir_p(default_bundle_path) }

    it "will not run a second concurrent bundle install until the lock is released" do
      thread = Thread.new do
        Bundler::ProcessLock.lock(default_bundle_path) do
          sleep 1 # ignore quality_spec
          expect(the_bundle).not_to include_gems "myrack 1.0"
        end
      end

      install_gemfile <<-G
        source "https://gem.repo1"
        gem "myrack"
      G

      thread.join
      expect(the_bundle).to include_gems "myrack 1.0"
    end

    context "when creating a lock raises Errno::ENOTSUP" do
      before { allow(File).to receive(:open).and_raise(Errno::ENOTSUP) }

      it "skips creating the lockfile and yields" do
        processed = false
        Bundler::ProcessLock.lock(default_bundle_path) { processed = true }

        expect(processed).to eq true
      end
    end

    context "when creating a lock raises Errno::EPERM" do
      before { allow(File).to receive(:open).and_raise(Errno::EPERM) }

      it "skips creating the lockfile and yields" do
        processed = false
        Bundler::ProcessLock.lock(default_bundle_path) { processed = true }

        expect(processed).to eq true
      end
    end

    context "when creating a lock raises Errno::EROFS" do
      before { allow(File).to receive(:open).and_raise(Errno::EROFS) }

      it "skips creating the lockfile and yields" do
        processed = false
        Bundler::ProcessLock.lock(default_bundle_path) { processed = true }

        expect(processed).to eq true
      end
    end

    it "refreshes gem specification cache after waiting for lock" do
      build_repo2 do
        build_gem "myrack", "1.0.0"
      end

      gemfile <<-G
        source "https://gem.repo2"
        gem "myrack"
      G

      # First, install the gem so it's available
      bundle "install"
      expect(out).to include("Installing myrack")

      # Queue for thread-safe communication
      lock_acquired = Queue.new
      can_release_lock = Queue.new
      install_output = Queue.new

      # Thread holds lock (simulating another bundle process that just finished installing)
      thread = Thread.new do
        Bundler::ProcessLock.lock(default_bundle_path) do
          # Signal that we have the lock
          lock_acquired << true
          # Wait until main thread signals we can release
          can_release_lock.pop
        end
      end

      # Wait for thread to acquire lock
      lock_acquired.pop

      # Start another install in a thread - it will wait for the lock
      install_thread = Thread.new do
        bundle "install", verbose: true
        install_output << out
      end

      # Give subprocess time to start and begin waiting for lock
      sleep 0.5

      # Signal thread to release the lock
      can_release_lock << true

      # Wait for both threads to complete
      thread.join
      install_thread.join

      second_install_out = install_output.pop

      expect(the_bundle).to include_gems "myrack 1.0.0"
      # The second install should have refreshed its cache after acquiring
      # the lock and seen that myrack was already installed
      expect(second_install_out).to include("Using myrack")
    end
  end
end
