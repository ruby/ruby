# frozen_string_literal: true

RSpec.describe "Bundler.with_env helpers" do
  def bundle_exec_ruby(args, options = {})
    build_bundler_context options
    bundle "exec '#{Gem.ruby}' #{args}", options
  end

  def build_bundler_context(options = {})
    bundle "config set path vendor/bundle"
    gemfile "source \"#{file_uri_for(gem_repo1)}\""
    bundle "install", options
  end

  def run_bundler_script(env, script)
    system(env, "ruby", "-I#{lib_dir}", "-rbundler", script.to_s)
  end

  describe "Bundler.original_env" do
    it "should return the PATH present before bundle was activated" do
      create_file("source.rb", <<-RUBY)
        print Bundler.original_env["PATH"]
      RUBY
      path = `getconf PATH`.strip + "#{File::PATH_SEPARATOR}/foo"
      with_path_as(path) do
        bundle_exec_ruby(bundled_app("source.rb").to_s)
        expect(last_command.stdboth).to eq(path)
      end
    end

    it "should return the GEM_PATH present before bundle was activated" do
      create_file("source.rb", <<-RUBY)
        print Bundler.original_env['GEM_PATH']
      RUBY
      gem_path = ENV["GEM_PATH"] + "#{File::PATH_SEPARATOR}/foo"
      with_gem_path_as(gem_path) do
        bundle_exec_ruby(bundled_app("source.rb").to_s)
        expect(last_command.stdboth).to eq(gem_path)
      end
    end

    it "works with nested bundle exec invocations", :ruby_repo do
      create_file("exe.rb", <<-'RUBY')
        count = ARGV.first.to_i
        exit if count < 0
        STDERR.puts "#{count} #{ENV["PATH"].end_with?("#{File::PATH_SEPARATOR}/foo")}"
        if count == 2
          ENV["PATH"] = "#{ENV["PATH"]}#{File::PATH_SEPARATOR}/foo"
        end
        exec(Gem.ruby, __FILE__, (count - 1).to_s)
      RUBY
      path = `getconf PATH`.strip + File::PATH_SEPARATOR + File.dirname(Gem.ruby)
      with_path_as(path) do
        build_bundler_context
        bundle_exec_ruby("#{bundled_app("exe.rb")} 2")
      end
      expect(err).to eq <<-EOS.strip
2 false
1 true
0 true
      EOS
    end

    it "removes variables that bundler added", :ruby_repo do
      # Simulate bundler has not yet been loaded
      ENV.replace(ENV.to_hash.delete_if {|k, _v| k.start_with?(Bundler::EnvironmentPreserver::BUNDLER_PREFIX) })

      original = ruby('puts ENV.to_a.map {|e| e.join("=") }.sort.join("\n")')
      create_file("source.rb", <<-RUBY)
        puts Bundler.original_env.to_a.map {|e| e.join("=") }.sort.join("\n")
      RUBY
      bundle_exec_ruby bundled_app("source.rb")
      expect(out).to eq original
    end
  end

  shared_examples_for "an unbundling helper" do
    it "should delete BUNDLE_PATH" do
      create_file("source.rb", <<-RUBY)
        print #{modified_env}.has_key?('BUNDLE_PATH')
      RUBY
      ENV["BUNDLE_PATH"] = "./foo"
      bundle_exec_ruby bundled_app("source.rb")
      expect(last_command.stdboth).to include "false"
    end

    it "should remove absolute path to 'bundler/setup' from RUBYOPT even if it was present in original env" do
      create_file("source.rb", <<-RUBY)
        print #{modified_env}['RUBYOPT']
      RUBY
      setup_require = "-r#{lib_dir}/bundler/setup"
      ENV["BUNDLER_ORIG_RUBYOPT"] = "-W2 #{setup_require} #{ENV["RUBYOPT"]}"
      simulate_bundler_version_when_missing_prerelease_default_gem_activation do
        bundle_exec_ruby bundled_app("source.rb")
      end
      expect(last_command.stdboth).not_to include(setup_require)
    end

    it "should remove relative path to 'bundler/setup' from RUBYOPT even if it was present in original env" do
      create_file("source.rb", <<-RUBY)
        print #{modified_env}['RUBYOPT']
      RUBY
      ENV["BUNDLER_ORIG_RUBYOPT"] = "-W2 -rbundler/setup #{ENV["RUBYOPT"]}"
      simulate_bundler_version_when_missing_prerelease_default_gem_activation do
        bundle_exec_ruby bundled_app("source.rb")
      end
      expect(last_command.stdboth).not_to include("-rbundler/setup")
    end

    it "should restore RUBYLIB", :ruby_repo do
      create_file("source.rb", <<-RUBY)
        print #{modified_env}['RUBYLIB']
      RUBY
      ENV["RUBYLIB"] = lib_dir.to_s + File::PATH_SEPARATOR + "/foo"
      ENV["BUNDLER_ORIG_RUBYLIB"] = lib_dir.to_s + File::PATH_SEPARATOR + "/foo-original"
      bundle_exec_ruby bundled_app("source.rb")
      expect(last_command.stdboth).to include("/foo-original")
    end

    it "should restore the original MANPATH" do
      create_file("source.rb", <<-RUBY)
        print #{modified_env}['MANPATH']
      RUBY
      ENV["MANPATH"] = "/foo"
      ENV["BUNDLER_ORIG_MANPATH"] = "/foo-original"
      bundle_exec_ruby bundled_app("source.rb")
      expect(last_command.stdboth).to include("/foo-original")
    end
  end

  describe "Bundler.unbundled_env" do
    let(:modified_env) { "Bundler.unbundled_env" }

    it_behaves_like "an unbundling helper"
  end

  describe "Bundler.clean_env", :bundler => 2 do
    let(:modified_env) { "Bundler.clean_env" }

    it_behaves_like "an unbundling helper"
  end

  describe "Bundler.with_original_env" do
    it "should set ENV to original_env in the block" do
      expected = Bundler.original_env
      actual = Bundler.with_original_env { Bundler::EnvironmentPreserver.env_to_hash(ENV) }
      expect(actual).to eq(expected)
    end

    it "should restore the environment after execution" do
      Bundler.with_original_env do
        ENV["FOO"] = "hello"
      end

      expect(ENV).not_to have_key("FOO")
    end
  end

  describe "Bundler.with_clean_env", :bundler => 2 do
    it "should set ENV to unbundled_env in the block" do
      expected = Bundler.unbundled_env

      actual = Bundler.ui.silence do
        Bundler.with_clean_env { Bundler::EnvironmentPreserver.env_to_hash(ENV) }
      end

      expect(actual).to eq(expected)
    end

    it "should restore the environment after execution" do
      Bundler.ui.silence do
        Bundler.with_clean_env { ENV["FOO"] = "hello" }
      end

      expect(ENV).not_to have_key("FOO")
    end
  end

  describe "Bundler.with_unbundled_env" do
    it "should set ENV to unbundled_env in the block" do
      expected = Bundler.unbundled_env
      actual = Bundler.with_unbundled_env { Bundler::EnvironmentPreserver.env_to_hash(ENV) }
      expect(actual).to eq(expected)
    end

    it "should restore the environment after execution" do
      Bundler.with_unbundled_env do
        ENV["FOO"] = "hello"
      end

      expect(ENV).not_to have_key("FOO")
    end
  end

  describe "Bundler.original_system" do
    before do
      create_file("source.rb", <<-'RUBY')
        Bundler.original_system("ruby", "-e", "exit(42) if ENV['BUNDLE_FOO'] == 'bar'")

        exit $?.exitstatus
      RUBY
    end

    it "runs system inside with_original_env" do
      run_bundler_script({ "BUNDLE_FOO" => "bar" }, bundled_app("source.rb"))
      expect($?.exitstatus).to eq(42)
    end
  end

  describe "Bundler.clean_system", :bundler => 2 do
    before do
      create_file("source.rb", <<-'RUBY')
        Bundler.ui.silence { Bundler.clean_system("ruby", "-e", "exit(42) unless ENV['BUNDLE_FOO'] == 'bar'") }

        exit $?.exitstatus
      RUBY
    end

    it "runs system inside with_clean_env" do
      run_bundler_script({ "BUNDLE_FOO" => "bar" }, bundled_app("source.rb"))
      expect($?.exitstatus).to eq(42)
    end
  end

  describe "Bundler.unbundled_system" do
    before do
      create_file("source.rb", <<-'RUBY')
        Bundler.unbundled_system("ruby", "-e", "exit(42) unless ENV['BUNDLE_FOO'] == 'bar'")

        exit $?.exitstatus
      RUBY
    end

    it "runs system inside with_unbundled_env" do
      run_bundler_script({ "BUNDLE_FOO" => "bar" }, bundled_app("source.rb"))
      expect($?.exitstatus).to eq(42)
    end
  end

  describe "Bundler.original_exec" do
    before do
      create_file("source.rb", <<-'RUBY')
        Process.fork do
          exit Bundler.original_exec(%(test "\$BUNDLE_FOO" = "bar"))
        end

        _, status = Process.wait2

        exit(status.exitstatus)
      RUBY
    end

    it "runs exec inside with_original_env" do
      skip "Fork not implemented" if Gem.win_platform?

      run_bundler_script({ "BUNDLE_FOO" => "bar" }, bundled_app("source.rb"))
      expect($?.exitstatus).to eq(0)
    end
  end

  describe "Bundler.clean_exec", :bundler => 2 do
    before do
      create_file("source.rb", <<-'RUBY')
        Process.fork do
          exit Bundler.ui.silence { Bundler.clean_exec(%(test "\$BUNDLE_FOO" = "bar")) }
        end

        _, status = Process.wait2

        exit(status.exitstatus)
      RUBY
    end

    it "runs exec inside with_clean_env" do
      skip "Fork not implemented" if Gem.win_platform?

      run_bundler_script({ "BUNDLE_FOO" => "bar" }, bundled_app("source.rb"))
      expect($?.exitstatus).to eq(1)
    end
  end

  describe "Bundler.unbundled_exec" do
    before do
      create_file("source.rb", <<-'RUBY')
        Process.fork do
          exit Bundler.unbundled_exec(%(test "\$BUNDLE_FOO" = "bar"))
        end

        _, status = Process.wait2

        exit(status.exitstatus)
      RUBY
    end

    it "runs exec inside with_clean_env" do
      skip "Fork not implemented" if Gem.win_platform?

      run_bundler_script({ "BUNDLE_FOO" => "bar" }, bundled_app("source.rb"))
      expect($?.exitstatus).to eq(1)
    end
  end
end
