# frozen_string_literal: true

RSpec.describe "process lock spec" do
  describe "when an install operation is already holding a process lock" do
    before { FileUtils.mkdir_p(default_bundle_path) }

    it "will not run a second concurrent bundle install until the lock is released" do
      thread = Thread.new do
        Bundler::ProcessLock.lock(default_bundle_path) do
          sleep 1 # ignore quality_spec
          expect(the_bundle).not_to include_gems "rack 1.0"
        end
      end

      install_gemfile! <<-G
        source "file://#{gem_repo1}"
        gem "rack"
      G

      thread.join
      expect(the_bundle).to include_gems "rack 1.0"
    end
  end
end
