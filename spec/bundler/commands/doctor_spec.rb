# frozen_string_literal: true

require "find"
require "stringio"
require "bundler/cli"
require "bundler/cli/doctor"
require "bundler/cli/doctor/diagnose"

RSpec.describe "bundle doctor" do
  before(:each) do
    install_gemfile <<-G
      source "https://gem.repo1"
      gem "myrack"
    G

    @stdout = StringIO.new

    [:error, :warn, :info].each do |method|
      allow(Bundler.ui).to receive(method).and_wrap_original do |m, message|
        m.call message
        @stdout.puts message
      end
    end
  end

  it "succeeds on a sane installation" do
    bundle :doctor
  end

  context "when all files in home are readable/writable" do
    before(:each) do
      stat = double("stat")
      unwritable_file = double("file")
      allow(Bundler::SharedHelpers).to receive(:find_gemfile).and_return(bundled_app_gemfile)
      allow(Find).to receive(:find).with(Bundler.bundle_path.to_s) { [unwritable_file] }
      allow(File).to receive(:exist?).and_call_original
      allow(File).to receive(:exist?).with(unwritable_file).and_return(true)
      allow(File).to receive(:stat).with(unwritable_file) { stat }
      allow(stat).to receive(:uid) { Process.uid }
      allow(File).to receive(:writable?).with(unwritable_file) { true }
      allow(File).to receive(:readable?).with(unwritable_file) { true }

      # The following lines are for `Gem::PathSupport#initialize`.
      allow(File).to receive(:exist?).with(Gem.default_dir)
      allow(File).to receive(:writable?).with(Gem.default_dir)
      allow(File).to receive(:writable?).with(File.expand_path("..", Gem.default_dir))
    end

    it "exits with a success message if the installed gem has no C extensions" do
      doctor = Bundler::CLI::Doctor::Diagnose.new({})
      allow(doctor).to receive(:lookup_with_fiddle).and_return(false)
      expect { doctor.run }.not_to raise_error
      expect(@stdout.string).to include("No issues")
    end

    it "exits with a success message if the installed gem's C extension dylib breakage is fine" do
      doctor = Bundler::CLI::Doctor::Diagnose.new({})
      expect(doctor).to receive(:bundles_for_gem).exactly(2).times.and_return ["/path/to/myrack/myrack.bundle"]
      expect(doctor).to receive(:dylibs).exactly(2).times.and_return ["/usr/lib/libSystem.dylib"]
      allow(doctor).to receive(:lookup_with_fiddle).with("/usr/lib/libSystem.dylib").and_return(false)
      expect { doctor.run }.not_to raise_error
      expect(@stdout.string).to include("No issues")
    end

    it "parses otool output correctly" do
      doctor = Bundler::CLI::Doctor::Diagnose.new({})
      expect(doctor).to receive(:`).with("/usr/bin/otool -L fake").and_return("/home/gem/ruby/3.4.3/gems/blake3-rb-1.5.4.4/lib/digest/blake3/blake3_ext.bundle:\n\t (compatibility version 0.0.0, current version 0.0.0)\n\t/usr/lib/libSystem.B.dylib (compatibility version 1.0.0, current version 1351.0.0)")
      expect(doctor.dylibs_darwin("fake")).to eq(["/usr/lib/libSystem.B.dylib"])
    end

    it "exits with a message if one of the linked libraries is missing" do
      doctor = Bundler::CLI::Doctor::Diagnose.new({})
      expect(doctor).to receive(:bundles_for_gem).exactly(2).times.and_return ["/path/to/myrack/myrack.bundle"]
      expect(doctor).to receive(:dylibs).exactly(2).times.and_return ["/usr/local/opt/icu4c/lib/libicui18n.57.1.dylib"]
      allow(doctor).to receive(:lookup_with_fiddle).with("/usr/local/opt/icu4c/lib/libicui18n.57.1.dylib").and_return(true)
      expect { doctor.run }.to raise_error(Bundler::ProductionError, <<~E.strip), @stdout.string
        The following gems are missing OS dependencies:
         * bundler: /usr/local/opt/icu4c/lib/libicui18n.57.1.dylib
         * myrack: /usr/local/opt/icu4c/lib/libicui18n.57.1.dylib
      E
    end
  end

  context "when home contains broken symlinks" do
    before(:each) do
      @broken_symlink = double("file")
      allow(Bundler::SharedHelpers).to receive(:find_gemfile).and_return(bundled_app_gemfile)
      allow(Find).to receive(:find).with(Bundler.bundle_path.to_s) { [@broken_symlink] }
      allow(File).to receive(:exist?).and_call_original
      allow(File).to receive(:exist?).with(@broken_symlink) { false }
    end

    it "exits with an error if home contains files that are not readable/writable" do
      doctor = Bundler::CLI::Doctor::Diagnose.new({})
      allow(doctor).to receive(:lookup_with_fiddle).and_return(false)
      expect { doctor.run }.not_to raise_error
      expect(@stdout.string).to include(
        "Broken links exist in the Bundler home. Please report them to the offending gem's upstream repo. These files are:\n - #{@broken_symlink}"
      )
      expect(@stdout.string).not_to include("No issues")
    end
  end

  context "when home contains files that are not readable/writable" do
    before(:each) do
      @stat = double("stat")
      @unwritable_file = double("file")
      allow(Bundler::SharedHelpers).to receive(:find_gemfile).and_return(bundled_app_gemfile)
      allow(Find).to receive(:find).with(Bundler.bundle_path.to_s) { [@unwritable_file] }
      allow(File).to receive(:exist?).and_call_original
      allow(File).to receive(:exist?).with(@unwritable_file) { true }
      allow(File).to receive(:stat).with(@unwritable_file) { @stat }
    end

    it "exits with an error if home contains files that are not readable" do
      doctor = Bundler::CLI::Doctor::Diagnose.new({})
      allow(doctor).to receive(:lookup_with_fiddle).and_return(false)
      allow(@stat).to receive(:uid) { Process.uid }
      allow(File).to receive(:writable?).with(@unwritable_file) { false }
      allow(File).to receive(:readable?).with(@unwritable_file) { false }
      expect { doctor.run }.not_to raise_error
      expect(@stdout.string).to include(
        "Files exist in the Bundler home that are not readable by the current user. These files are:\n - #{@unwritable_file}"
      )
      expect(@stdout.string).not_to include("No issues")
    end

    it "exits without an error if home contains files that are not writable" do
      doctor = Bundler::CLI::Doctor::Diagnose.new({})
      allow(doctor).to receive(:lookup_with_fiddle).and_return(false)
      allow(@stat).to receive(:uid) { Process.uid }
      allow(File).to receive(:writable?).with(@unwritable_file) { false }
      allow(File).to receive(:readable?).with(@unwritable_file) { true }
      expect { doctor.run }.not_to raise_error
      expect(@stdout.string).not_to include(
        "Files exist in the Bundler home that are not readable by the current user. These files are:\n - #{@unwritable_file}"
      )
      expect(@stdout.string).to include("No issues")
    end

    context "when home contains files that are not owned by the current process", :permissions do
      before(:each) do
        allow(@stat).to receive(:uid) { 0o0000 }
      end

      it "exits with an error if home contains files that are not readable/writable and are not owned by the current user" do
        doctor = Bundler::CLI::Doctor::Diagnose.new({})
        allow(doctor).to receive(:lookup_with_fiddle).and_return(false)
        allow(File).to receive(:writable?).with(@unwritable_file) { false }
        allow(File).to receive(:readable?).with(@unwritable_file) { false }
        expect { doctor.run }.not_to raise_error
        expect(@stdout.string).to include(
          "Files exist in the Bundler home that are owned by another user, and are not readable. These files are:\n - #{@unwritable_file}"
        )
        expect(@stdout.string).not_to include("No issues")
      end

      it "exits with a warning if home contains files that are read/write but not owned by current user" do
        doctor = Bundler::CLI::Doctor::Diagnose.new({})
        allow(doctor).to receive(:lookup_with_fiddle).and_return(false)
        allow(File).to receive(:writable?).with(@unwritable_file) { true }
        allow(File).to receive(:readable?).with(@unwritable_file) { true }
        expect { doctor.run }.not_to raise_error
        expect(@stdout.string).to include(
          "Files exist in the Bundler home that are owned by another user, but are still readable. These files are:\n - #{@unwritable_file}"
        )
        expect(@stdout.string).not_to include("No issues")
      end
    end
  end

  context "when home contains filenames with special characters" do
    it "escape filename before command execute" do
      doctor = Bundler::CLI::Doctor::Diagnose.new({})
      expect(doctor).to receive(:`).with("/usr/bin/otool -L \\$\\(date\\)\\ \\\"\\'\\\\.bundle").and_return("dummy string")
      doctor.dylibs_darwin('$(date) "\'\.bundle')
      expect(doctor).to receive(:`).with("/usr/bin/ldd \\$\\(date\\)\\ \\\"\\'\\\\.bundle").and_return("dummy string")
      doctor.dylibs_ldd('$(date) "\'\.bundle')
    end
  end
end
