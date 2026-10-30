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

    it "keeps excluding late arrivals after the lock is handed over to a waiting process" do
      events = Queue.new
      release_waiter = Queue.new

      # The warning printed while blocking on the lock is the only observable
      # sign that a contender has opened the lock file and is waiting on it
      allow(Gem).to receive(:warn) do |message|
        events << [Thread.current.name, :waiting] if message.include?("Waiting for another process")
      end

      next_event = lambda do
        events.pop(timeout: 10) || raise("Timed out waiting for a lock event")
      end

      contender = lambda do |name, &block|
        Thread.new do
          Thread.current.name = name
          Thread.current.abort_on_exception = true
          Bundler::ProcessLock.lock(default_bundle_path) do
            events << [name, :locked]
            block&.call
          end
        end
      end

      waiter = nil
      Bundler::ProcessLock.lock(default_bundle_path) do
        waiter = contender.call("waiter") { release_waiter.pop }
        expect(next_event.call).to eq(["waiter", :waiting])
      end
      expect(next_event.call).to eq(["waiter", :locked])

      # Arrives only after the original holder is gone, while the waiter is
      # still inside its critical section
      late_arrival = contender.call("late_arrival")
      expect(next_event.call).to eq(["late_arrival", :waiting])

      release_waiter << true
      [waiter, late_arrival].each(&:join)
      expect(next_event.call).to eq(["late_arrival", :locked])
      expect(default_bundle_path("bundler.lock")).not_to exist
    ensure
      # Never leave the waiter blocked while holding the lock
      release_waiter << true
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
