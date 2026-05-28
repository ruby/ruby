# frozen_string_literal: true

RSpec.describe Bundler::Resolver do
  let(:resolver) { described_class.allocate }

  def remote(cooldown:)
    instance_double(Bundler::Source::Rubygems::Remote, effective_cooldown: cooldown)
  end

  def spec(created_at:, remote:)
    Struct.new(:created_at, :remote).new(created_at, remote)
  end

  describe "#filter_cooldown" do
    let(:now) { Time.now }

    context "with a 7-day cooldown" do
      let(:r) { remote(cooldown: 7) }

      it "rejects versions published within the window" do
        recent = spec(created_at: now - (2 * 86_400), remote: r)
        old = spec(created_at: now - (30 * 86_400), remote: r)

        expect(resolver.send(:filter_cooldown, [recent, old])).to eq([old])
      end

      it "keeps versions published exactly at the threshold" do
        boundary = spec(created_at: now - (7 * 86_400), remote: r)

        expect(resolver.send(:filter_cooldown, [boundary])).to eq([boundary])
      end

      it "leaves rolling-delay history intact" do
        # 7-day cooldown with frequent releases must still expose an older candidate.
        in_cooldown = spec(created_at: now - 86_400, remote: r)
        also_in_cooldown = spec(created_at: now - (3 * 86_400), remote: r)
        eligible = spec(created_at: now - (10 * 86_400), remote: r)

        result = resolver.send(:filter_cooldown, [in_cooldown, also_in_cooldown, eligible])

        expect(result).to eq([eligible])
      end
    end

    context "when created_at is missing (blank metadata)" do
      it "keeps the spec regardless of cooldown" do
        s = spec(created_at: nil, remote: remote(cooldown: 7))

        expect(resolver.send(:filter_cooldown, [s])).to eq([s])
      end
    end

    context "when the remote has no cooldown" do
      it "keeps every spec" do
        s = spec(created_at: now - 3600, remote: remote(cooldown: nil))

        expect(resolver.send(:filter_cooldown, [s])).to eq([s])
      end
    end

    context "when cooldown is 0" do
      it "keeps every spec (escape hatch)" do
        s = spec(created_at: now - 3600, remote: remote(cooldown: 0))

        expect(resolver.send(:filter_cooldown, [s])).to eq([s])
      end
    end

    context "when the spec does not respond to created_at" do
      it "keeps the spec" do
        bare = Struct.new(:version).new("1.0.0")

        expect(resolver.send(:filter_cooldown, [bare])).to eq([bare])
      end
    end

    context "when the spec has no remote" do
      it "keeps the spec" do
        s = spec(created_at: now - 86_400, remote: nil)

        expect(resolver.send(:filter_cooldown, [s])).to eq([s])
      end
    end

    it "returns the same array when input is empty" do
      expect(resolver.send(:filter_cooldown, [])).to eq([])
    end
  end

  describe "#cooldown_hint" do
    let(:now) { Time.now }
    let(:r) { remote(cooldown: 7) }

    it "returns nil when no spec is excluded" do
      expect(resolver.send(:cooldown_hint, [])).to be_nil
    end

    it "returns nil when every spec is outside the cooldown window" do
      eligible = [spec(created_at: now - (30 * 86_400), remote: r)]

      expect(resolver.send(:cooldown_hint, eligible)).to be_nil
    end

    it "mentions the count and the bypass flag for one excluded version" do
      excluded = [spec(created_at: now - 86_400, remote: r)]

      hint = resolver.send(:cooldown_hint, excluded)

      expect(hint).to match(/1 version excluded by the cooldown setting/)
      expect(hint).to match(/--cooldown 0/)
    end

    it "uses plural wording when multiple versions are excluded" do
      excluded = Array.new(3) { spec(created_at: now - 86_400, remote: r) }

      expect(resolver.send(:cooldown_hint, excluded)).to match(/3 versions excluded/)
    end
  end
end
