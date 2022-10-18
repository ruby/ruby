# frozen_string_literal: true

RSpec.describe Bundler::GemVersionPromoter do
  context "conservative resolver" do
    def versions(result)
      result.flatten.map(&:version).map(&:to_s)
    end

    def make_instance(*args)
      @gvp = Bundler::GemVersionPromoter.new(*args).tap do |gvp|
        gvp.class.class_eval { public :filter_dep_specs, :sort_dep_specs }
      end
    end

    def unlocking(options)
      make_instance(Bundler::SpecSet.new([]), ["foo"]).tap do |p|
        p.level = options[:level] if options[:level]
        p.strict = options[:strict] if options[:strict]
      end
    end

    def keep_locked(options)
      make_instance(Bundler::SpecSet.new([]), ["bar"]).tap do |p|
        p.level = options[:level] if options[:level]
        p.strict = options[:strict] if options[:strict]
      end
    end

    def build_spec_groups(name, versions)
      versions.map do |v|
        Bundler::Resolver::SpecGroup.new(build_spec(name, v), [Gem::Platform::RUBY])
      end
    end

    # Rightmost (highest array index) in result is most preferred.
    # Leftmost (lowest array index) in result is least preferred.
    # `build_spec_groups` has all versions of gem in index.
    # `build_spec` is the version currently in the .lock file.
    #
    # In default (not strict) mode, all versions in the index will
    # be returned, allowing Bundler the best chance to resolve all
    # dependencies, but sometimes resulting in upgrades that some
    # would not consider conservative.
    context "filter specs (strict) level patch" do
      it "when keeping build_spec, keep current, next release" do
        keep_locked(:level => :patch)
        res = @gvp.filter_dep_specs(
          build_spec_groups("foo", %w[1.7.8 1.7.9 1.8.0]),
          build_spec("foo", "1.7.8").first
        )
        expect(versions(res)).to eq %w[1.7.9 1.7.8]
      end

      it "when unlocking prefer next release first" do
        unlocking(:level => :patch)
        res = @gvp.filter_dep_specs(
          build_spec_groups("foo", %w[1.7.8 1.7.9 1.8.0]),
          build_spec("foo", "1.7.8").first
        )
        expect(versions(res)).to eq %w[1.7.8 1.7.9]
      end

      it "when unlocking keep current when already at latest release" do
        unlocking(:level => :patch)
        res = @gvp.filter_dep_specs(
          build_spec_groups("foo", %w[1.7.9 1.8.0 2.0.0]),
          build_spec("foo", "1.7.9").first
        )
        expect(versions(res)).to eq %w[1.7.9]
      end
    end

    context "filter specs (strict) level minor" do
      it "when unlocking favor next releases, remove minor and major increases" do
        unlocking(:level => :minor)
        res = @gvp.filter_dep_specs(
          build_spec_groups("foo", %w[0.2.0 0.3.0 0.3.1 0.9.0 1.0.0 2.0.0 2.0.1]),
          build_spec("foo", "0.2.0").first
        )
        expect(versions(res)).to eq %w[0.2.0 0.3.0 0.3.1 0.9.0]
      end

      it "when keep locked, keep current, then favor next release, remove minor and major increases" do
        keep_locked(:level => :minor)
        res = @gvp.filter_dep_specs(
          build_spec_groups("foo", %w[0.2.0 0.3.0 0.3.1 0.9.0 1.0.0 2.0.0 2.0.1]),
          build_spec("foo", "0.2.0").first
        )
        expect(versions(res)).to eq %w[0.3.0 0.3.1 0.9.0 0.2.0]
      end
    end

    context "sort specs (not strict) level patch" do
      it "when not unlocking, same order but make sure build_spec version is most preferred to stay put" do
        keep_locked(:level => :patch)
        res = @gvp.sort_dep_specs(
          build_spec_groups("foo", %w[1.5.4 1.6.5 1.7.6 1.7.7 1.7.8 1.7.9 1.8.0 1.8.1 2.0.0 2.0.1]),
          build_spec("foo", "1.7.7").first
        )
        expect(versions(res)).to eq %w[1.5.4 1.6.5 1.7.6 2.0.0 2.0.1 1.8.0 1.8.1 1.7.8 1.7.9 1.7.7]
      end

      it "when unlocking favor next release, then current over minor increase" do
        unlocking(:level => :patch)
        res = @gvp.sort_dep_specs(
          build_spec_groups("foo", %w[1.7.7 1.7.8 1.7.9 1.8.0]),
          build_spec("foo", "1.7.8").first
        )
        expect(versions(res)).to eq %w[1.7.7 1.8.0 1.7.8 1.7.9]
      end

      it "when unlocking do proper integer comparison, not string" do
        unlocking(:level => :patch)
        res = @gvp.sort_dep_specs(
          build_spec_groups("foo", %w[1.7.7 1.7.8 1.7.9 1.7.15 1.8.0]),
          build_spec("foo", "1.7.8").first
        )
        expect(versions(res)).to eq %w[1.7.7 1.8.0 1.7.8 1.7.9 1.7.15]
      end

      it "leave current when unlocking but already at latest release" do
        unlocking(:level => :patch)
        res = @gvp.sort_dep_specs(
          build_spec_groups("foo", %w[1.7.9 1.8.0 2.0.0]),
          build_spec("foo", "1.7.9").first
        )
        expect(versions(res)).to eq %w[2.0.0 1.8.0 1.7.9]
      end
    end

    context "sort specs (not strict) level minor" do
      it "when unlocking favor next release, then minor increase over current" do
        unlocking(:level => :minor)
        res = @gvp.sort_dep_specs(
          build_spec_groups("foo", %w[0.2.0 0.3.0 0.3.1 0.9.0 1.0.0 2.0.0 2.0.1]),
          build_spec("foo", "0.2.0").first
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
