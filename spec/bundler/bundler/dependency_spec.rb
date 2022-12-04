# frozen_string_literal: true

RSpec.describe Bundler::Dependency do
  let(:options) do
    {}
  end
  let(:dependency) do
    described_class.new(
      "test_gem",
      "1.0.0",
      options
    )
  end

  describe "to_lock" do
    it "returns formatted string" do
      expect(dependency.to_lock).to eq("  test_gem (= 1.0.0)")
    end

    it "matches format of Gem::Dependency#to_lock" do
      gem_dependency = Gem::Dependency.new("test_gem", "1.0.0")
      expect(dependency.to_lock).to eq(gem_dependency.to_lock)
    end

    context "when source is passed" do
      let(:options) do
        {
          "source" => Bundler::Source::Git.new({}),
        }
      end

      it "returns formatted string with exclamation mark" do
        expect(dependency.to_lock).to eq("  test_gem (= 1.0.0)!")
      end
    end
  end

  describe "PLATFORM_MAP" do
    subject { described_class::PLATFORM_MAP }

    # rubocop:disable Naming/VariableNumber
    let(:platforms) do
      { :ruby => Gem::Platform::RUBY,
        :ruby_18 => Gem::Platform::RUBY,
        :ruby_19 => Gem::Platform::RUBY,
        :ruby_20 => Gem::Platform::RUBY,
        :ruby_21 => Gem::Platform::RUBY,
        :ruby_22 => Gem::Platform::RUBY,
        :ruby_23 => Gem::Platform::RUBY,
        :ruby_24 => Gem::Platform::RUBY,
        :ruby_25 => Gem::Platform::RUBY,
        :ruby_26 => Gem::Platform::RUBY,
        :ruby_27 => Gem::Platform::RUBY,
        :ruby_30 => Gem::Platform::RUBY,
        :ruby_31 => Gem::Platform::RUBY,
        :mri => Gem::Platform::RUBY,
        :mri_18 => Gem::Platform::RUBY,
        :mri_19 => Gem::Platform::RUBY,
        :mri_20 => Gem::Platform::RUBY,
        :mri_21 => Gem::Platform::RUBY,
        :mri_22 => Gem::Platform::RUBY,
        :mri_23 => Gem::Platform::RUBY,
        :mri_24 => Gem::Platform::RUBY,
        :mri_25 => Gem::Platform::RUBY,
        :mri_26 => Gem::Platform::RUBY,
        :mri_27 => Gem::Platform::RUBY,
        :mri_30 => Gem::Platform::RUBY,
        :mri_31 => Gem::Platform::RUBY,
        :rbx => Gem::Platform::RUBY,
        :truffleruby => Gem::Platform::RUBY,
        :jruby => Gem::Platform::JAVA,
        :jruby_18 => Gem::Platform::JAVA,
        :jruby_19 => Gem::Platform::JAVA,
        :windows => Gem::Platform::WINDOWS,
        :windows_18 => Gem::Platform::WINDOWS,
        :windows_19 => Gem::Platform::WINDOWS,
        :windows_20 => Gem::Platform::WINDOWS,
        :windows_21 => Gem::Platform::WINDOWS,
        :windows_22 => Gem::Platform::WINDOWS,
        :windows_23 => Gem::Platform::WINDOWS,
        :windows_24 => Gem::Platform::WINDOWS,
        :windows_25 => Gem::Platform::WINDOWS,
        :windows_26 => Gem::Platform::WINDOWS,
        :windows_27 => Gem::Platform::WINDOWS,
        :windows_30 => Gem::Platform::WINDOWS,
        :windows_31 => Gem::Platform::WINDOWS,
        :mswin => Gem::Platform::MSWIN,
        :mswin_18 => Gem::Platform::MSWIN,
        :mswin_19 => Gem::Platform::MSWIN,
        :mswin_20 => Gem::Platform::MSWIN,
        :mswin_21 => Gem::Platform::MSWIN,
        :mswin_22 => Gem::Platform::MSWIN,
        :mswin_23 => Gem::Platform::MSWIN,
        :mswin_24 => Gem::Platform::MSWIN,
        :mswin_25 => Gem::Platform::MSWIN,
        :mswin_26 => Gem::Platform::MSWIN,
        :mswin_27 => Gem::Platform::MSWIN,
        :mswin_30 => Gem::Platform::MSWIN,
        :mswin_31 => Gem::Platform::MSWIN,
        :mswin64 => Gem::Platform::MSWIN64,
        :mswin64_19 => Gem::Platform::MSWIN64,
        :mswin64_20 => Gem::Platform::MSWIN64,
        :mswin64_21 => Gem::Platform::MSWIN64,
        :mswin64_22 => Gem::Platform::MSWIN64,
        :mswin64_23 => Gem::Platform::MSWIN64,
        :mswin64_24 => Gem::Platform::MSWIN64,
        :mswin64_25 => Gem::Platform::MSWIN64,
        :mswin64_26 => Gem::Platform::MSWIN64,
        :mswin64_27 => Gem::Platform::MSWIN64,
        :mswin64_30 => Gem::Platform::MSWIN64,
        :mswin64_31 => Gem::Platform::MSWIN64,
        :mingw => Gem::Platform::MINGW,
        :mingw_18 => Gem::Platform::MINGW,
        :mingw_19 => Gem::Platform::MINGW,
        :mingw_20 => Gem::Platform::MINGW,
        :mingw_21 => Gem::Platform::MINGW,
        :mingw_22 => Gem::Platform::MINGW,
        :mingw_23 => Gem::Platform::MINGW,
        :mingw_24 => Gem::Platform::MINGW,
        :mingw_25 => Gem::Platform::MINGW,
        :mingw_26 => Gem::Platform::MINGW,
        :mingw_27 => Gem::Platform::MINGW,
        :mingw_30 => Gem::Platform::MINGW,
        :mingw_31 => Gem::Platform::MINGW,
        :x64_mingw => Gem::Platform::X64_MINGW,
        :x64_mingw_20 => Gem::Platform::X64_MINGW,
        :x64_mingw_21 => Gem::Platform::X64_MINGW,
        :x64_mingw_22 => Gem::Platform::X64_MINGW,
        :x64_mingw_23 => Gem::Platform::X64_MINGW,
        :x64_mingw_24 => Gem::Platform::X64_MINGW,
        :x64_mingw_25 => Gem::Platform::X64_MINGW,
        :x64_mingw_26 => Gem::Platform::X64_MINGW,
        :x64_mingw_27 => Gem::Platform::X64_MINGW,
        :x64_mingw_30 => Gem::Platform::X64_MINGW,
        :x64_mingw_31 => Gem::Platform::X64_MINGW }
    end
    # rubocop:enable Naming/VariableNumber

    it "includes all platforms" do
      expect(subject).to eq(platforms)
    end
  end
end
