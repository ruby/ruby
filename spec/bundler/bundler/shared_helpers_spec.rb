# frozen_string_literal: true

RSpec.describe Bundler::SharedHelpers do
  let(:ext_lock_double) { double(:ext_lock) }

  before do
    pwd_stub
    allow(Bundler.rubygems).to receive(:ext_lock).and_return(ext_lock_double)
    allow(ext_lock_double).to receive(:synchronize) {|&block| block.call }
  end

  let(:pwd_stub) { allow(subject).to receive(:pwd).and_return(bundled_app) }

  subject { Bundler::SharedHelpers }

  describe "#default_gemfile" do
    before { ENV["BUNDLE_GEMFILE"] = "/path/Gemfile" }

    context "Gemfile is present" do
      let(:expected_gemfile_path) { Pathname.new("/path/Gemfile").expand_path }

      it "returns the Gemfile path" do
        expect(subject.default_gemfile).to eq(expected_gemfile_path)
      end
    end

    context "Gemfile is not present" do
      before { ENV["BUNDLE_GEMFILE"] = nil }

      it "raises a GemfileNotFound error" do
        expect { subject.default_gemfile }.to raise_error(
          Bundler::GemfileNotFound, "Could not locate Gemfile"
        )
      end
    end

    context "Gemfile is not an absolute path" do
      before { ENV["BUNDLE_GEMFILE"] = "Gemfile" }

      let(:expected_gemfile_path) { Pathname.new("Gemfile").expand_path }

      it "returns the Gemfile path" do
        expect(subject.default_gemfile).to eq(expected_gemfile_path)
      end
    end
  end

  describe "#default_lockfile" do
    context "gemfile is gems.rb" do
      let(:gemfile_path)           { Pathname.new("/path/gems.rb") }
      let(:expected_lockfile_path) { Pathname.new("/path/gems.locked") }

      before { allow(subject).to receive(:default_gemfile).and_return(gemfile_path) }

      it "returns the gems.locked path" do
        expect(subject.default_lockfile).to eq(expected_lockfile_path)
      end
    end

    context "is a regular Gemfile" do
      let(:gemfile_path)           { Pathname.new("/path/Gemfile") }
      let(:expected_lockfile_path) { Pathname.new("/path/Gemfile.lock") }

      before { allow(subject).to receive(:default_gemfile).and_return(gemfile_path) }

      it "returns the lock file path" do
        expect(subject.default_lockfile).to eq(expected_lockfile_path)
      end
    end
  end

  describe "#default_bundle_dir" do
    context ".bundle does not exist" do
      it "returns nil" do
        expect(subject.default_bundle_dir).to be_nil
      end
    end

    context ".bundle is global .bundle" do
      let(:global_rubygems_dir) { Pathname.new(bundled_app) }

      before do
        Dir.mkdir bundled_app(".bundle")
        allow(Bundler.rubygems).to receive(:user_home).and_return(global_rubygems_dir)
      end

      it "returns nil" do
        expect(subject.default_bundle_dir).to be_nil
      end
    end

    context ".bundle is not global .bundle" do
      let(:global_rubygems_dir)      { Pathname.new("/path/rubygems") }
      let(:expected_bundle_dir_path) { Pathname.new("#{bundled_app}/.bundle") }

      before do
        Dir.mkdir bundled_app(".bundle")
        allow(Bundler.rubygems).to receive(:user_home).and_return(global_rubygems_dir)
      end

      it "returns the .bundle path" do
        expect(subject.default_bundle_dir).to eq(expected_bundle_dir_path)
      end
    end
  end

  describe "#in_bundle?" do
    it "calls the find_gemfile method" do
      expect(subject).to receive(:find_gemfile)
      subject.in_bundle?
    end

    shared_examples_for "correctly determines whether to return a Gemfile path" do
      context "currently in directory with a Gemfile" do
        before { FileUtils.touch(bundled_app_gemfile) }
        after { FileUtils.rm(bundled_app_gemfile) }

        it "returns path of the bundle Gemfile" do
          expect(subject.in_bundle?).to eq("#{bundled_app}/Gemfile")
        end
      end

      context "currently in directory without a Gemfile" do
        it "returns nil" do
          expect(subject.in_bundle?).to be_nil
        end
      end
    end

    context "ENV['BUNDLE_GEMFILE'] set" do
      before { ENV["BUNDLE_GEMFILE"] = "/path/Gemfile" }

      it "returns ENV['BUNDLE_GEMFILE']" do
        expect(subject.in_bundle?).to eq("/path/Gemfile")
      end
    end

    context "ENV['BUNDLE_GEMFILE'] not set" do
      before { ENV["BUNDLE_GEMFILE"] = nil }

      it_behaves_like "correctly determines whether to return a Gemfile path"
    end

    context "ENV['BUNDLE_GEMFILE'] is blank" do
      before { ENV["BUNDLE_GEMFILE"] = "" }

      it_behaves_like "correctly determines whether to return a Gemfile path"
    end
  end

  describe "#chdir" do
    let(:op_block) { proc { Dir.mkdir "nested_dir" } }

    before { Dir.mkdir bundled_app("chdir_test_dir") }

    it "executes the passed block while in the specified directory" do
      subject.chdir(bundled_app("chdir_test_dir"), &op_block)
      expect(bundled_app("chdir_test_dir/nested_dir")).to exist
    end
  end

  describe "#pwd" do
    let(:pwd_stub) { nil }

    it "returns the current absolute path" do
      expect(subject.pwd).to eq(source_root)
    end
  end

  describe "#with_clean_git_env" do
    let(:with_clean_git_env_block) { proc { Dir.mkdir bundled_app("with_clean_git_env_test_dir") } }

    before do
      ENV["GIT_DIR"] = "ORIGINAL_ENV_GIT_DIR"
      ENV["GIT_WORK_TREE"] = "ORIGINAL_ENV_GIT_WORK_TREE"
    end

    it "executes the passed block" do
      subject.with_clean_git_env(&with_clean_git_env_block)
      expect(bundled_app("with_clean_git_env_test_dir")).to exist
    end

    context "when a block is passed" do
      let(:with_clean_git_env_block) do
        proc do
          Dir.mkdir bundled_app("git_dir_test_dir") unless ENV["GIT_DIR"].nil?
          Dir.mkdir bundled_app("git_work_tree_test_dir") unless ENV["GIT_WORK_TREE"].nil?
        end end

      it "uses a fresh git env for execution" do
        subject.with_clean_git_env(&with_clean_git_env_block)
        expect(bundled_app("git_dir_test_dir")).to_not exist
        expect(bundled_app("git_work_tree_test_dir")).to_not exist
      end
    end

    context "passed block does not throw errors" do
      let(:with_clean_git_env_block) do
        proc do
          ENV["GIT_DIR"] = "NEW_ENV_GIT_DIR"
          ENV["GIT_WORK_TREE"] = "NEW_ENV_GIT_WORK_TREE"
        end end

      it "restores the git env after" do
        subject.with_clean_git_env(&with_clean_git_env_block)
        expect(ENV["GIT_DIR"]).to eq("ORIGINAL_ENV_GIT_DIR")
        expect(ENV["GIT_WORK_TREE"]).to eq("ORIGINAL_ENV_GIT_WORK_TREE")
      end
    end

    context "passed block throws errors" do
      let(:with_clean_git_env_block) do
        proc do
          ENV["GIT_DIR"] = "NEW_ENV_GIT_DIR"
          ENV["GIT_WORK_TREE"] = "NEW_ENV_GIT_WORK_TREE"
          raise RuntimeError.new
        end end

      it "restores the git env after" do
        expect { subject.with_clean_git_env(&with_clean_git_env_block) }.to raise_error(RuntimeError)
        expect(ENV["GIT_DIR"]).to eq("ORIGINAL_ENV_GIT_DIR")
        expect(ENV["GIT_WORK_TREE"]).to eq("ORIGINAL_ENV_GIT_WORK_TREE")
      end
    end
  end

  describe "#set_bundle_environment" do
    before do
      ENV["BUNDLE_GEMFILE"] = "Gemfile"
    end

    shared_examples_for "ENV['PATH'] gets set correctly" do
      before { Dir.mkdir bundled_app(".bundle") }

      it "ensures bundle bin path is in ENV['PATH']" do
        subject.set_bundle_environment
        paths = ENV["PATH"].split(File::PATH_SEPARATOR)
        expect(paths).to include("#{Bundler.bundle_path}/bin")
      end
    end

    shared_examples_for "ENV['RUBYOPT'] gets set correctly" do
      it "ensures -rbundler/setup is at the beginning of ENV['RUBYOPT']" do
        subject.set_bundle_environment
        expect(ENV["RUBYOPT"].split(" ")).to start_with("-r#{source_lib_dir}/bundler/setup")
      end
    end

    shared_examples_for "ENV['BUNDLER_SETUP'] gets set correctly" do
      it "ensures bundler/setup is set in ENV['BUNDLER_SETUP']" do
        subject.set_bundle_environment
        expect(ENV["BUNDLER_SETUP"]).to eq("#{source_lib_dir}/bundler/setup")
      end
    end

    shared_examples_for "ENV['RUBYLIB'] gets set correctly" do
      let(:ruby_lib_path) { "stubbed_ruby_lib_dir" }

      before do
        allow(subject).to receive(:bundler_ruby_lib).and_return(ruby_lib_path)
      end

      it "ensures bundler's ruby version lib path is in ENV['RUBYLIB']" do
        subject.set_bundle_environment
        paths = (ENV["RUBYLIB"]).split(File::PATH_SEPARATOR)
        expect(paths).to include(ruby_lib_path)
      end
    end

    it "calls the appropriate set methods" do
      expect(subject).to receive(:set_bundle_variables)
      expect(subject).to receive(:set_path)
      expect(subject).to receive(:set_rubyopt)
      expect(subject).to receive(:set_rubylib)
      subject.set_bundle_environment
    end

    it "ignores if bundler_ruby_lib is same as rubylibdir" do
      allow(subject).to receive(:bundler_ruby_lib).and_return(RbConfig::CONFIG["rubylibdir"])

      subject.set_bundle_environment

      paths = (ENV["RUBYLIB"]).split(File::PATH_SEPARATOR)
      expect(paths.count(RbConfig::CONFIG["rubylibdir"])).to eq(0)
    end

    it "exits if bundle path contains the unix-like path separator" do
      if Gem.respond_to?(:path_separator)
        allow(Gem).to receive(:path_separator).and_return(":")
      else
        stub_const("File::PATH_SEPARATOR", ":")
      end
      allow(Bundler).to receive(:bundle_path) { Pathname.new("so:me/dir/bin") }
      expect { subject.send(:validate_bundle_path) }.to raise_error(
        Bundler::PathError,
        "Your bundle path contains text matching \":\", which is the " \
        "path separator for your system. Bundler cannot " \
        "function correctly when the Bundle path contains the " \
        "system's PATH separator. Please change your " \
        "bundle path to not match \":\".\nYour current bundle " \
        "path is '#{Bundler.bundle_path}'."
      )
    end

    context "with a jruby path_separator regex" do
      # In versions of jruby that supported ruby 1.8, the path separator was the standard File::PATH_SEPARATOR
      let(:regex) { Regexp.new("(?<!jar:file|jar|file|classpath|uri:classloader|uri|http|https):") }
      it "does not exit if bundle path is the standard uri path" do
        allow(Bundler.rubygems).to receive(:path_separator).and_return(regex)
        allow(Bundler).to receive(:bundle_path) { Pathname.new("uri:classloader:/WEB-INF/gems") }
        expect { subject.send(:validate_bundle_path) }.not_to raise_error
      end

      it "exits if bundle path contains another directory" do
        allow(Bundler.rubygems).to receive(:path_separator).and_return(regex)
        allow(Bundler).to receive(:bundle_path) {
          Pathname.new("uri:classloader:/WEB-INF/gems:other/dir")
        }

        expect { subject.send(:validate_bundle_path) }.to raise_error(
          Bundler::PathError,
          "Your bundle path contains text matching " \
          "/(?<!jar:file|jar|file|classpath|uri:classloader|uri|http|https):/, which is the " \
          "path separator for your system. Bundler cannot " \
          "function correctly when the Bundle path contains the " \
          "system's PATH separator. Please change your " \
          "bundle path to not match " \
          "/(?<!jar:file|jar|file|classpath|uri:classloader|uri|http|https):/." \
          "\nYour current bundle path is '#{Bundler.bundle_path}'."
        )
      end
    end

    context "ENV['PATH'] does not exist" do
      before { ENV.delete("PATH") }

      it_behaves_like "ENV['PATH'] gets set correctly"
    end

    context "ENV['PATH'] is empty" do
      before { ENV["PATH"] = "" }

      it_behaves_like "ENV['PATH'] gets set correctly"
    end

    context "ENV['PATH'] exists" do
      before { ENV["PATH"] = "/some_path/bin" }

      it_behaves_like "ENV['PATH'] gets set correctly"
    end

    context "ENV['PATH'] already contains the bundle bin path" do
      let(:bundle_path) { "#{Bundler.bundle_path}/bin" }

      before do
        ENV["PATH"] = bundle_path
      end

      it_behaves_like "ENV['PATH'] gets set correctly"

      it "ENV['PATH'] should only contain one instance of bundle bin path" do
        subject.set_bundle_environment
        paths = (ENV["PATH"]).split(File::PATH_SEPARATOR)
        expect(paths.count(bundle_path)).to eq(1)
      end
    end

    context "ENV['RUBYOPT'] does not exist" do
      before { ENV.delete("RUBYOPT") }

      it_behaves_like "ENV['RUBYOPT'] gets set correctly"
    end

    context "ENV['RUBYOPT'] exists without -rbundler/setup" do
      before { ENV["RUBYOPT"] = "-I/some_app_path/lib" }

      it_behaves_like "ENV['RUBYOPT'] gets set correctly"
    end

    context "ENV['RUBYOPT'] exists and contains -rbundler/setup" do
      before { ENV["RUBYOPT"] = "-rbundler/setup" }

      it_behaves_like "ENV['RUBYOPT'] gets set correctly"
    end

    context "ENV['RUBYLIB'] does not exist" do
      before { ENV.delete("RUBYLIB") }

      it_behaves_like "ENV['RUBYLIB'] gets set correctly"
    end

    context "ENV['RUBYLIB'] is empty" do
      before { ENV["PATH"] = "" }

      it_behaves_like "ENV['RUBYLIB'] gets set correctly"
    end

    context "ENV['RUBYLIB'] exists" do
      before { ENV["PATH"] = "/some_path/bin" }

      it_behaves_like "ENV['RUBYLIB'] gets set correctly"
    end

    context "bundle executable in ENV['BUNDLE_BIN_PATH'] does not exist" do
      before { ENV["BUNDLE_BIN_PATH"] = "/does/not/exist" }
      before { Bundler.rubygems.replace_bin_path [] }

      it "sets BUNDLE_BIN_PATH to the bundle executable file" do
        subject.set_bundle_environment
        bin_path = ENV["BUNDLE_BIN_PATH"]
        expect(bin_path).to eq(bindir.join("bundle").to_s)
        expect(File.exist?(bin_path)).to be true
      end
    end

    context "ENV['RUBYLIB'] already contains the bundler's ruby version lib path" do
      let(:ruby_lib_path) { "stubbed_ruby_lib_dir" }

      before do
        ENV["RUBYLIB"] = ruby_lib_path
      end

      it_behaves_like "ENV['RUBYLIB'] gets set correctly"

      it "ENV['RUBYLIB'] should only contain one instance of bundler's ruby version lib path" do
        subject.set_bundle_environment
        paths = (ENV["RUBYLIB"]).split(File::PATH_SEPARATOR)
        expect(paths.count(ruby_lib_path)).to eq(1)
      end
    end
  end

  describe "#filesystem_access" do
    context "system has proper permission access" do
      let(:file_op_block) { proc {|path| FileUtils.mkdir_p(path) } }

      it "performs the operation in the passed block" do
        subject.filesystem_access(bundled_app("test_dir"), &file_op_block)
        expect(bundled_app("test_dir")).to exist
      end
    end

    context "system throws Errno::EACESS" do
      let(:file_op_block) { proc {|_path| raise Errno::EACCES } }

      it "raises a PermissionError" do
        expect { subject.filesystem_access("/path", &file_op_block) }.to raise_error(
          Bundler::PermissionError
        )
      end
    end

    context "system throws Errno::EAGAIN" do
      let(:file_op_block) { proc {|_path| raise Errno::EAGAIN } }

      it "raises a TemporaryResourceError" do
        expect { subject.filesystem_access("/path", &file_op_block) }.to raise_error(
          Bundler::TemporaryResourceError
        )
      end
    end

    context "system throws Errno::EPROTO" do
      let(:file_op_block) { proc {|_path| raise Errno::EPROTO } }

      it "raises a VirtualProtocolError" do
        expect { subject.filesystem_access("/path", &file_op_block) }.to raise_error(
          Bundler::VirtualProtocolError
        )
      end
    end

    context "system throws Errno::ENOTSUP" do
      let(:file_op_block) { proc {|_path| raise Errno::ENOTSUP } }

      it "raises a OperationNotSupportedError" do
        expect { subject.filesystem_access("/path", &file_op_block) }.to raise_error(
          Bundler::OperationNotSupportedError
        )
      end
    end

    context "system throws Errno::ENOSPC" do
      let(:file_op_block) { proc {|_path| raise Errno::ENOSPC } }

      it "raises a NoSpaceOnDeviceError" do
        expect { subject.filesystem_access("/path", &file_op_block) }.to raise_error(
          Bundler::NoSpaceOnDeviceError
        )
      end
    end

    context "system throws an unhandled SystemCallError" do
      let(:error) { SystemCallError.new("Shields down", 1337) }
      let(:file_op_block) { proc {|_path| raise error } }

      it "raises a GenericSystemCallError" do
        expect { subject.filesystem_access("/path", &file_op_block) }.to raise_error(
          Bundler::GenericSystemCallError, /error accessing.+underlying.+Shields down/m
        )
      end
    end
  end
end
