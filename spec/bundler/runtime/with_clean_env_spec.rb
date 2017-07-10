# frozen_string_literal: true
require "spec_helper"

describe "Bundler.with_env helpers" do
  describe "Bundler.original_env" do
    before do
      gemfile ""
      bundle "install --path vendor/bundle"
    end

    it "should return the PATH present before bundle was activated" do
      code = "print Bundler.original_env['PATH']"
      path = `getconf PATH`.strip + "#{File::PATH_SEPARATOR}/foo"
      with_path_as(path) do
        result = bundle("exec ruby -e #{code.dump}")
        expect(result).to eq(path)
      end
    end

    it "should return the GEM_PATH present before bundle was activated" do
      code = "print Bundler.original_env['GEM_PATH']"
      gem_path = ENV["GEM_PATH"] + ":/foo"
      with_gem_path_as(gem_path) do
        result = bundle("exec ruby -e #{code.inspect}")
        expect(result).to eq(gem_path)
      end
    end

    it "works with nested bundle exec invocations" do
      create_file("exe.rb", <<-'RB')
        count = ARGV.first.to_i
        exit if count < 0
        STDERR.puts "#{count} #{ENV["PATH"].end_with?(":/foo")}"
        if count == 2
          ENV["PATH"] = "#{ENV["PATH"]}:/foo"
        end
        exec("ruby", __FILE__, (count - 1).to_s)
      RB
      path = `getconf PATH`.strip + File::PATH_SEPARATOR + File.dirname(Gem.ruby)
      with_path_as(path) do
        bundle!("exec ruby #{bundled_app("exe.rb")} 2")
      end
      expect(err).to eq <<-EOS.strip
2 false
1 true
0 true
      EOS
    end
  end

  describe "Bundler.clean_env" do
    before do
      gemfile ""
      bundle "install --path vendor/bundle"
    end

    it "should delete BUNDLE_PATH" do
      code = "print Bundler.clean_env.has_key?('BUNDLE_PATH')"
      ENV["BUNDLE_PATH"] = "./foo"
      result = bundle("exec ruby -e #{code.inspect}")
      expect(result).to eq("false")
    end

    it "should remove '-rbundler/setup' from RUBYOPT" do
      code = "print Bundler.clean_env['RUBYOPT']"
      ENV["RUBYOPT"] = "-W2 -rbundler/setup"
      result = bundle("exec ruby -e #{code.inspect}")
      expect(result).not_to include("-rbundler/setup")
    end

    it "should clean up RUBYLIB" do
      code = "print Bundler.clean_env['RUBYLIB']"
      ENV["RUBYLIB"] = File.expand_path("../../../lib", __FILE__) + File::PATH_SEPARATOR + "/foo"
      result = bundle("exec ruby -e #{code.inspect}")
      expect(result).to eq("/foo")
    end

    it "should restore the original MANPATH" do
      code = "print Bundler.clean_env['MANPATH']"
      ENV["MANPATH"] = "/foo"
      ENV["BUNDLER_ORIG_MANPATH"] = "/foo-original"
      result = bundle("exec ruby -e #{code.inspect}")
      expect(result).to eq("/foo-original")
    end
  end

  describe "Bundler.with_original_env" do
    it "should set ENV to original_env in the block" do
      expected = Bundler.original_env
      actual = Bundler.with_original_env { ENV.to_hash }
      expect(actual).to eq(expected)
    end

    it "should restore the environment after execution" do
      Bundler.with_original_env do
        ENV["FOO"] = "hello"
      end

      expect(ENV).not_to have_key("FOO")
    end
  end

  describe "Bundler.with_clean_env" do
    it "should set ENV to clean_env in the block" do
      expected = Bundler.clean_env
      actual = Bundler.with_clean_env { ENV.to_hash }
      expect(actual).to eq(expected)
    end

    it "should restore the environment after execution" do
      Bundler.with_clean_env do
        ENV["FOO"] = "hello"
      end

      expect(ENV).not_to have_key("FOO")
    end
  end

  describe "Bundler.clean_system", :ruby => ">= 1.9" do
    it "runs system inside with_clean_env" do
      Bundler.clean_system(%(echo 'if [ "$BUNDLE_PATH" = "" ]; then exit 42; else exit 1; fi' | /bin/sh))
      expect($?.exitstatus).to eq(42)
    end
  end

  describe "Bundler.clean_exec", :ruby => ">= 1.9" do
    it "runs exec inside with_clean_env" do
      pid = Kernel.fork do
        Bundler.clean_exec(%(echo 'if [ "$BUNDLE_PATH" = "" ]; then exit 42; else exit 1; fi' | /bin/sh))
      end
      Process.wait(pid)
      expect($?.exitstatus).to eq(42)
    end
  end
end
