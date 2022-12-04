# frozen_string_literal: true

RSpec.describe Bundler::GemVersionPromoter do
  context "conservative resolver" do
    def versions(result)
      result.flatten.map(&:version).map(&:to_s)
    end

    def make_instance
      @gvp = Bundler::GemVersionPromoter.new.tap do |gvp|
        gvp.class.class_eval { public :filter_dep_specs, :sort_dep_specs }
      end
    end

    def with_options(options)
      make_instance.tap do |p|
        p.level = options[:level] if options[:level]
        p.strict = options[:strict] if options[:strict]
      end
    end

    def build_candidates(versions)
      versions.map do |v|
        Bundler::Resolver::Candidate.new(v)
      end
    end

    def build_spec_set(name, v)
      Bundler::SpecSet.new(build_spec(name, v))
    end

    # Rightmost (highest array index) in result is most preferred.
    # Leftmost (lowest array index) in result is least preferred.
    # `build_candidates` has all versions of gem in index.
    # `build_spec` is the version currently in the .lock file.
    #
    # In default (not strict) mode, all versions in the index will
    # be returned, allowing Bundler the best chance to resolve all
    # dependencies, but sometimes resulting in upgrades that some
    # would not consider conservative.
    context "filter specs (strict) level patch" do
      it "when keeping build_spec, keep current, next release" do
        with_options(:level => :patch)
        res = @gvp.filter_dep_specs(
          build_candidates(%w[1.7.8 1.7.9 1.8.0]),
          Bundler::Resolver::Package.new("foo", [], build_spec_set("foo", "1.7.8"), [])
        )
        expect(versions(res)).to match_array %w[1.7.9 1.7.8]
      end

      it "when unlocking prefer next release first" do
        with_options(:level => :patch)
        res = @gvp.filter_dep_specs(
          build_candidates(%w[1.7.8 1.7.9 1.8.0]),
          Bundler::Resolver::Package.new("foo", [], build_spec_set("foo", "1.7.8"), [])
        )
        expect(versions(res)).to eq %w[1.7.8 1.7.9]
      end

      it "when unlocking keep current when already at latest release" do
        with_options(:level => :patch)
        res = @gvp.filter_dep_specs(
          build_candidates(%w[1.7.9 1.8.0 2.0.0]),
          Bundler::Resolver::Package.new("foo", [], build_spec_set("foo", "1.7.9"), [])
        )
        expect(versions(res)).to eq %w[1.7.9]
      end
    end

    context "filter specs (strict) level minor" do
      it "when unlocking favor next releases, remove minor and major increases" do
        with_options(:level => :minor)
        res = @gvp.filter_dep_specs(
          build_candidates(%w[0.2.0 0.3.0 0.3.1 0.9.0 1.0.0 2.0.0 2.0.1]),
          Bundler::Resolver::Package.new("foo", [], build_spec_set("foo", "0.2.0"), [])
        )
        expect(versions(res)).to eq %w[0.2.0 0.3.0 0.3.1 0.9.0]
      end

      it "when keep locked, keep current, then favor next release, remove minor and major increases" do
        with_options(:level => :minor)
        res = @gvp.filter_dep_specs(
          build_candidates(%w[0.2.0 0.3.0 0.3.1 0.9.0 1.0.0 2.0.0 2.0.1]),
          Bundler::Resolver::Package.new("foo", [], build_spec_set("foo", "0.2.0"), ["bar"])
        )
        expect(versions(res)).to match_array %w[0.3.0 0.3.1 0.9.0 0.2.0]
      end
    end

    context "sort specs (not strict) level patch" do
      it "when not unlocking, same order but make sure build_spec version is most preferred to stay put" do
        with_options(:level => :patch)
        res = @gvp.sort_dep_specs(
          build_candidates(%w[1.5.4 1.6.5 1.7.6 1.7.7 1.7.8 1.7.9 1.8.0 1.8.1 2.0.0 2.0.1]),
          Bundler::Resolver::Package.new("foo", [], build_spec_set("foo", "1.7.7"), ["bar"])
        )
        expect(versions(res)).to eq %w[1.5.4 1.6.5 1.7.6 2.0.0 2.0.1 1.8.0 1.8.1 1.7.8 1.7.9 1.7.7]
      end

      it "when unlocking favor next release, then current over minor increase" do
        with_options(:level => :patch)
        res = @gvp.sort_dep_specs(
          build_candidates(%w[1.7.7 1.7.8 1.7.9 1.8.0]),
          Bundler::Resolver::Package.new("foo", [], build_spec_set("foo", "1.7.8"), [])
        )
        expect(versions(res)).to eq %w[1.7.7 1.8.0 1.7.8 1.7.9]
      end

      it "when unlocking do proper integer comparison, not string" do
        with_options(:level => :patch)
        res = @gvp.sort_dep_specs(
          build_candidates(%w[1.7.7 1.7.8 1.7.9 1.7.15 1.8.0]),
          Bundler::Resolver::Package.new("foo", [], build_spec_set("foo", "1.7.8"), [])
        )
        expect(versions(res)).to eq %w[1.7.7 1.8.0 1.7.8 1.7.9 1.7.15]
      end

      it "leave current when unlocking but already at latest release" do
        with_options(:level => :patch)
        res = @gvp.sort_dep_specs(
          build_candidates(%w[1.7.9 1.8.0 2.0.0]),
          Bundler::Resolver::Package.new("foo", [], build_spec_set("foo", "1.7.9"), [])
        )
        expect(versions(res)).to eq %w[2.0.0 1.8.0 1.7.9]
      end
    end

    context "sort specs (not strict) level minor" do
      it "when unlocking favor next release, then minor increase over current" do
        with_options(:level => :minor)
        res = @gvp.sort_dep_specs(
          build_candidates(%w[0.2.0 0.3.0 0.3.1 0.9.0 1.0.0 2.0.0 2.0.1]),
          Bundler::Resolver::Package.new("foo", [], build_spec_set("foo", "0.2.0"), [])
        )
        expect(versions(res)).to eq %w[2.0.0 2.0.1 1.0.0 0.2.0 0.3.0 0.3.1 0.9.0]
      end
    end

    context "level error handling" do
      subject { Bundler::GemVersionPromoter.new }

      it "should raise if not major, minor or patch is passed" do
        expect { subject.level = :minjor }.to raise_error ArgumentError
      end

      it "should raise if invalid classes passed" do
        [123, nil].each do |value|
          expect { subject.level = value }.to raise_error ArgumentError
        end
      end

      it "should accept major, minor patch symbols" do
        [:major, :minor, :patch].each do |value|
          subject.level = value
          expect(subject.level).to eq value
        end
      end

      it "should accept major, minor patch strings" do
        %w[major minor patch].each do |value|
          subject.level = value
          expect(subject.level).to eq value.to_sym
        end
      end
    end
  end
end
