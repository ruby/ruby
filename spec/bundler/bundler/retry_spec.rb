# frozen_string_literal: true

RSpec.describe Bundler::Retry do
  it "return successful result if no errors" do
    attempts = 0
    result = Bundler::Retry.new(nil, nil, 3).attempt do
      attempts += 1
      :success
    end
    expect(result).to eq(:success)
    expect(attempts).to eq(1)
  end

  it "returns the first valid result" do
    jobs = [proc { raise "job 1 failed" }, proc { :bar }, proc { raise "job 2 failed" }]
    attempts = 0
    result = Bundler::Retry.new(nil, nil, 3).attempt do
      attempts += 1
      jobs.shift.call
    end
    expect(result).to eq(:bar)
    expect(attempts).to eq(2)
  end

  it "raises the last error" do
    errors = [StandardError, StandardError, StandardError, Bundler::GemfileNotFound]
    attempts = 0
    expect do
      Bundler::Retry.new(nil, nil, 3).attempt do
        attempts += 1
        raise errors.shift
      end
    end.to raise_error(Bundler::GemfileNotFound)
    expect(attempts).to eq(4)
  end

  it "raises exceptions" do
    error = Bundler::GemfileNotFound
    attempts = 0
    expect do
      Bundler::Retry.new(nil, error).attempt do
        attempts += 1
        raise error
      end
    end.to raise_error(error)
    expect(attempts).to eq(1)
  end

  context "logging" do
    let(:error)           { Bundler::GemfileNotFound }
    let(:failure_message) { "Retrying test due to error (2/2): #{error} #{error}" }

    context "with debugging on" do
      it "print error message with newline" do
        allow(Bundler.ui).to receive(:debug?).and_return(true)
        expect(Bundler.ui).to_not receive(:info)
        expect(Bundler.ui).to receive(:warn).with(failure_message, true)

        expect do
          Bundler::Retry.new("test", [], 1).attempt do
            raise error
          end
        end.to raise_error(error)
      end
    end

    context "with debugging off" do
      it "print error message with newlines" do
        allow(Bundler.ui).to  receive(:debug?).and_return(false)
        expect(Bundler.ui).to receive(:info).with("").twice
        expect(Bundler.ui).to receive(:warn).with(failure_message, true)

        expect do
          Bundler::Retry.new("test", [], 1).attempt do
            raise error
          end
        end.to raise_error(error)
      end
    end
  end

  context "exponential backoff" do
    it "can be disabled by setting base_delay to 0" do
      attempts = 0
      expect do
        Bundler::Retry.new("test", [], 2, base_delay: 0).attempt do
          attempts += 1
          raise "error"
        end
      end.to raise_error(StandardError)

      # Verify no sleep was called (implicitly - if sleep was called, timing would be different)
      expect(attempts).to eq(3)
    end

    it "is enabled by default with 1 second base delay" do
      original_base_delay = Bundler::Retry.default_base_delay
      Bundler::Retry.default_base_delay = 1.0

      attempts = 0
      sleep_times = []

      allow_any_instance_of(Bundler::Retry).to receive(:sleep) do |_instance, delay|
        sleep_times << delay
      end

      expect do
        Bundler::Retry.new("test", [], 2, jitter: 0).attempt do
          attempts += 1
          raise "error"
        end
      end.to raise_error(StandardError)

      expect(attempts).to eq(3)
      expect(sleep_times.length).to eq(2)
      # First retry: 1.0 * 2^0 = 1.0
      expect(sleep_times[0]).to eq(1.0)
      # Second retry: 1.0 * 2^1 = 2.0
      expect(sleep_times[1]).to eq(2.0)
    ensure
      Bundler::Retry.default_base_delay = original_base_delay
    end

    it "sleeps with exponential backoff when base_delay is set" do
      attempts = 0
      sleep_times = []

      allow_any_instance_of(Bundler::Retry).to receive(:sleep) do |_instance, delay|
        sleep_times << delay
      end

      expect do
        Bundler::Retry.new("test", [], 2, base_delay: 1.0, jitter: 0).attempt do
          attempts += 1
          raise "error"
        end
      end.to raise_error(StandardError)

      expect(attempts).to eq(3)
      expect(sleep_times.length).to eq(2)
      # First retry: 1.0 * 2^0 = 1.0
      expect(sleep_times[0]).to eq(1.0)
      # Second retry: 1.0 * 2^1 = 2.0
      expect(sleep_times[1]).to eq(2.0)
    end

    it "respects max_delay" do
      sleep_times = []

      allow_any_instance_of(Bundler::Retry).to receive(:sleep) do |_instance, delay|
        sleep_times << delay
      end

      expect do
        Bundler::Retry.new("test", [], 3, base_delay: 10.0, max_delay: 15.0, jitter: 0).attempt do
          raise "error"
        end
      end.to raise_error(StandardError)

      # First retry: 10.0 * 2^0 = 10.0
      expect(sleep_times[0]).to eq(10.0)
      # Second retry: 10.0 * 2^1 = 20.0, capped at 15.0
      expect(sleep_times[1]).to eq(15.0)
      # Third retry: 10.0 * 2^2 = 40.0, capped at 15.0
      expect(sleep_times[2]).to eq(15.0)
    end

    it "adds jitter to delay" do
      sleep_times = []

      allow_any_instance_of(Bundler::Retry).to receive(:sleep) do |_instance, delay|
        sleep_times << delay
      end

      expect do
        Bundler::Retry.new("test", [], 2, base_delay: 1.0, jitter: 0.5).attempt do
          raise "error"
        end
      end.to raise_error(StandardError)

      expect(sleep_times.length).to eq(2)
      # First retry should be between 1.0 and 1.5 (base + jitter)
      expect(sleep_times[0]).to be >= 1.0
      expect(sleep_times[0]).to be <= 1.5
      # Second retry should be between 2.0 and 2.5
      expect(sleep_times[1]).to be >= 2.0
      expect(sleep_times[1]).to be <= 2.5
    end
  end
end
