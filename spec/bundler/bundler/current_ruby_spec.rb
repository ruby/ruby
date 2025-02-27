# frozen_string_literal: true

RSpec.describe Bundler::CurrentRuby do
  describe "PLATFORM_MAP" do
    subject { described_class::PLATFORM_MAP }

    # rubocop:disable Naming/VariableNumber
    let(:platforms) do
      { ruby: Gem::Platform::RUBY,
        ruby_18: Gem::Platform::RUBY,
        ruby_19: Gem::Platform::RUBY,
        ruby_20: Gem::Platform::RUBY,
        ruby_21: Gem::Platform::RUBY,
        ruby_22: Gem::Platform::RUBY,
        ruby_23: Gem::Platform::RUBY,
        ruby_24: Gem::Platform::RUBY,
        ruby_25: Gem::Platform::RUBY,
        ruby_26: Gem::Platform::RUBY,
        ruby_27: Gem::Platform::RUBY,
        ruby_30: Gem::Platform::RUBY,
        ruby_31: Gem::Platform::RUBY,
        ruby_32: Gem::Platform::RUBY,
        ruby_33: Gem::Platform::RUBY,
        ruby_34: Gem::Platform::RUBY,
        ruby_35: Gem::Platform::RUBY,
        mri: Gem::Platform::RUBY,
        mri_18: Gem::Platform::RUBY,
        mri_19: Gem::Platform::RUBY,
        mri_20: Gem::Platform::RUBY,
        mri_21: Gem::Platform::RUBY,
        mri_22: Gem::Platform::RUBY,
        mri_23: Gem::Platform::RUBY,
        mri_24: Gem::Platform::RUBY,
        mri_25: Gem::Platform::RUBY,
        mri_26: Gem::Platform::RUBY,
        mri_27: Gem::Platform::RUBY,
        mri_30: Gem::Platform::RUBY,
        mri_31: Gem::Platform::RUBY,
        mri_32: Gem::Platform::RUBY,
        mri_33: Gem::Platform::RUBY,
        mri_34: Gem::Platform::RUBY,
        mri_35: Gem::Platform::RUBY,
        rbx: Gem::Platform::RUBY,
        truffleruby: Gem::Platform::RUBY,
        jruby: Gem::Platform::JAVA,
        jruby_18: Gem::Platform::JAVA,
        jruby_19: Gem::Platform::JAVA,
        windows: Gem::Platform::WINDOWS,
        windows_18: Gem::Platform::WINDOWS,
        windows_19: Gem::Platform::WINDOWS,
        windows_20: Gem::Platform::WINDOWS,
        windows_21: Gem::Platform::WINDOWS,
        windows_22: Gem::Platform::WINDOWS,
        windows_23: Gem::Platform::WINDOWS,
        windows_24: Gem::Platform::WINDOWS,
        windows_25: Gem::Platform::WINDOWS,
        windows_26: Gem::Platform::WINDOWS,
        windows_27: Gem::Platform::WINDOWS,
        windows_30: Gem::Platform::WINDOWS,
        windows_31: Gem::Platform::WINDOWS,
        windows_32: Gem::Platform::WINDOWS,
        windows_33: Gem::Platform::WINDOWS,
        windows_34: Gem::Platform::WINDOWS,
        windows_35: Gem::Platform::WINDOWS }
    end

    let(:deprecated) do
      { mswin: Gem::Platform::MSWIN,
        mswin_18: Gem::Platform::MSWIN,
        mswin_19: Gem::Platform::MSWIN,
        mswin_20: Gem::Platform::MSWIN,
        mswin_21: Gem::Platform::MSWIN,
        mswin_22: Gem::Platform::MSWIN,
        mswin_23: Gem::Platform::MSWIN,
        mswin_24: Gem::Platform::MSWIN,
        mswin_25: Gem::Platform::MSWIN,
        mswin_26: Gem::Platform::MSWIN,
        mswin_27: Gem::Platform::MSWIN,
        mswin_30: Gem::Platform::MSWIN,
        mswin_31: Gem::Platform::MSWIN,
        mswin_32: Gem::Platform::MSWIN,
        mswin_33: Gem::Platform::MSWIN,
        mswin_34: Gem::Platform::MSWIN,
        mswin_35: Gem::Platform::MSWIN,
        mswin64: Gem::Platform::MSWIN64,
        mswin64_19: Gem::Platform::MSWIN64,
        mswin64_20: Gem::Platform::MSWIN64,
        mswin64_21: Gem::Platform::MSWIN64,
        mswin64_22: Gem::Platform::MSWIN64,
        mswin64_23: Gem::Platform::MSWIN64,
        mswin64_24: Gem::Platform::MSWIN64,
        mswin64_25: Gem::Platform::MSWIN64,
        mswin64_26: Gem::Platform::MSWIN64,
        mswin64_27: Gem::Platform::MSWIN64,
        mswin64_30: Gem::Platform::MSWIN64,
        mswin64_31: Gem::Platform::MSWIN64,
        mswin64_32: Gem::Platform::MSWIN64,
        mswin64_33: Gem::Platform::MSWIN64,
        mswin64_34: Gem::Platform::MSWIN64,
        mswin64_35: Gem::Platform::MSWIN64,
        mingw: Gem::Platform::UNIVERSAL_MINGW,
        mingw_18: Gem::Platform::UNIVERSAL_MINGW,
        mingw_19: Gem::Platform::UNIVERSAL_MINGW,
        mingw_20: Gem::Platform::UNIVERSAL_MINGW,
        mingw_21: Gem::Platform::UNIVERSAL_MINGW,
        mingw_22: Gem::Platform::UNIVERSAL_MINGW,
        mingw_23: Gem::Platform::UNIVERSAL_MINGW,
        mingw_24: Gem::Platform::UNIVERSAL_MINGW,
        mingw_25: Gem::Platform::UNIVERSAL_MINGW,
        mingw_26: Gem::Platform::UNIVERSAL_MINGW,
        mingw_27: Gem::Platform::UNIVERSAL_MINGW,
        mingw_30: Gem::Platform::UNIVERSAL_MINGW,
        mingw_31: Gem::Platform::UNIVERSAL_MINGW,
        mingw_32: Gem::Platform::UNIVERSAL_MINGW,
        mingw_33: Gem::Platform::UNIVERSAL_MINGW,
        mingw_34: Gem::Platform::UNIVERSAL_MINGW,
        mingw_35: Gem::Platform::UNIVERSAL_MINGW,
        x64_mingw: Gem::Platform::UNIVERSAL_MINGW,
        x64_mingw_20: Gem::Platform::UNIVERSAL_MINGW,
        x64_mingw_21: Gem::Platform::UNIVERSAL_MINGW,
        x64_mingw_22: Gem::Platform::UNIVERSAL_MINGW,
        x64_mingw_23: Gem::Platform::UNIVERSAL_MINGW,
        x64_mingw_24: Gem::Platform::UNIVERSAL_MINGW,
        x64_mingw_25: Gem::Platform::UNIVERSAL_MINGW,
        x64_mingw_26: Gem::Platform::UNIVERSAL_MINGW,
        x64_mingw_27: Gem::Platform::UNIVERSAL_MINGW,
        x64_mingw_30: Gem::Platform::UNIVERSAL_MINGW,
        x64_mingw_31: Gem::Platform::UNIVERSAL_MINGW,
        x64_mingw_32: Gem::Platform::UNIVERSAL_MINGW,
        x64_mingw_33: Gem::Platform::UNIVERSAL_MINGW,
        x64_mingw_34: Gem::Platform::UNIVERSAL_MINGW,
        x64_mingw_35: Gem::Platform::UNIVERSAL_MINGW }
    end
    # rubocop:enable Naming/VariableNumber

    it "includes all platforms" do
      expect(subject).to eq(platforms.merge(deprecated))
    end
  end

  describe "Deprecated platform" do
    it "Outputs a deprecation warning when calling maglev?", bundler: "< 3" do
      expect(Bundler.ui).to receive(:warn).with(/`CurrentRuby#maglev\?` is deprecated with no replacement./)

      Bundler.current_ruby.maglev?
    end

    it "Outputs a deprecation warning when calling maglev_31?", bundler: "< 3" do
      expect(Bundler.ui).to receive(:warn).with(/`CurrentRuby#maglev_31\?` is deprecated with no replacement./)

      Bundler.current_ruby.maglev_31?
    end

    pending "is removed and shows a helpful error message about it", bundler: "3"
  end
end
