# frozen_string_literal: true

RSpec.describe "Bundler.with_env helpers" do
  def bundle_exec_ruby!(code)
    build_bundler_context
    bundle! "exec '#{Gem.ruby}' -e #{code}"
  end

  def build_bundler_context
    bundle "config set path vendor/bundle"
    gemfile ""
    bundle "install"
  end

  describe "Bundler.original_env" do
    it "should return the PATH present before bundle was activated" do
      code = "print Bundler.original_env['PATH']"
      path = `getconf PATH`.strip + "#{File::PATH_SEPARATOR}/foo"
      with_path_as(path) do
        bundle_exec_ruby!(code.dump)
        expect(last_command.stdboth).to eq(path)
      end
    end

    it "should return the GEM_PATH present before bundle was activated" do
      code = "print Bundler.original_env['GEM_PATH']"
      gem_path = ENV["GEM_PATH"] + ":/foo"
      with_gem_path_as(gem_path) do
        bundle_exec_ruby!(code.dump)
        expect(last_command.stdboth).to eq(gem_path)
      end
    end

    it "works with nested bundle exec invocations", :ruby_repo do
      create_file("exe.rb", <<-'RB')
        count = ARGV.first.to_i
        exit if count < 0
        STDERR.puts "#{count} #{ENV["PATH"].end_with?(":/foo")}"
        if count == 2
          ENV["PATH"] = "#{ENV["PATH"]}:/foo"
        end
        exec(Gem.ruby, __FILE__, (count - 1).to_s)
      RB
      path = `getconf PATH`.strip + File::PATH_SEPARATOR + File.dirname(Gem.ruby)
      with_path_as(path) do
        build_bundler_context
        bundle! "exec '#{Gem.ruby}' #{bundled_app("exe.rb")} 2"
      end
      expect(last_command.stderr).to eq <<-EOS.strip
2 false
1 true
0 true
      EOS
    end

    it "removes variables that bundler added", :ruby_repo do
      original = ruby!('puts ENV.to_a.map {|e| e.join("=") }.sort.join("\n")')
      code = 'puts Bundler.original_env.to_a.map {|e| e.join("=") }.sort.join("\n")'
      bundle_exec_ruby! code.dump
      expect(out).to eq original
    end
  end

  shared_examples_for "an unbundling helper" do
    it "should delete BUNDLE_PATH" do
      code = "print #{modified_env}.has_key?('BUNDLE_PATH')"
      ENV["BUNDLE_PATH"] = "./foo"
      bundle_exec_ruby! code.dump
      expect(last_command.stdboth).to include "false"
    end

    it "should remove '-rbundler/setup' from RUBYOPT" do
      code = "print #{modified_env}['RUBYOPT']"
      ENV["RUBYOPT"] = "-W2 -rbundler/setup #{ENV["RUBYOPT"]}"
      bundle_exec_ruby! code.dump
      expect(last_command.stdboth).not_to include("-rbundler/setup")
    end

    it "should clean up RUBYLIB", :ruby_repo do
      code = "print #{modified_env}['RUBYLIB']"
      ENV["RUBYLIB"] = root.join("lib").to_s + File::PATH_SEPARATOR + "/foo"
      bundle_exec_ruby! code.dump
      expect(last_command.stdboth).to include("/foo")
    end

    it "should restore the original MANPATH" do
      code = "print #{modified_env}['MANPATH']"
      ENV["MANPATH"] = "/foo"
      ENV["BUNDLER_ORIG_MANPATH"] = "/foo-original"
      bundle_exec_ruby! code.dump
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

  describe "Bundler.with_clean_env", :bundler => 2 do
    it "should set ENV to unbundled_env in the block" do
      expected = Bundler.unbundled_env
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

  describe "Bundler.with_unbundled_env" do
    it "should set ENV to unbundled_env in the block" do
      expected = Bundler.unbundled_env
      actual = Bundler.with_unbundled_env { ENV.to_hash }
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
    it "runs system inside with_original_env" do
      code = 'exit Bundler.original_system(%(test "\$BUNDLE_FOO" = "bar"))'
      lib = File.expand_path("../../lib", __dir__)
      system({ "BUNDLE_FOO" => "bar" }, "ruby -I#{lib} -rbundler -e '#{code}'")
      expect($?.exitstatus).to eq(0)
    end
  end

  describe "Bundler.clean_system", :bundler => 2 do
    it "runs system inside with_clean_env" do
      code = 'exit Bundler.clean_system(%(test "\$BUNDLE_FOO" = "bar"))'
      lib = File.expand_path("../../lib", __dir__)
      system({ "BUNDLE_FOO" => "bar" }, "ruby -I#{lib} -rbundler -e '#{code}'")
      expect($?.exitstatus).to eq(1)
    end
  end

  describe "Bundler.unbundled_system" do
    it "runs system inside with_unbundled_env" do
      code = 'exit Bundler.clean_system(%(test "\$BUNDLE_FOO" = "bar"))'
      lib = File.expand_path("../../lib", __dir__)
      system({ "BUNDLE_FOO" => "bar" }, "ruby -I#{lib} -rbundler -e '#{code}'")
      expect($?.exitstatus).to eq(1)
    end
  end

  describe "Bundler.original_exec" do
    let(:code) do
      <<~RUBY
        Process.fork do
          exit Bundler.original_exec(%(test "\$BUNDLE_FOO" = "bar"))
        end

        _, status = Process.wait2

        exit(status.exitstatus)
      RUBY
    end

    it "runs exec inside with_original_env" do
      lib = File.expand_path("../../lib", __dir__)
      system({ "BUNDLE_FOO" => "bar" }, "ruby -I#{lib} -rbundler -e '#{code}'")
      expect($?.exitstatus).to eq(0)
    end
  end

  describe "Bundler.clean_exec", :bundler => 2 do
    let(:code) do
      <<~RUBY
        Process.fork do
          exit Bundler.clean_exec(%(test "\$BUNDLE_FOO" = "bar"))
        end

        _, status = Process.wait2

        exit(status.exitstatus)
      RUBY
    end

    it "runs exec inside with_clean_env" do
      lib = File.expand_path("../../lib", __dir__)
      system({ "BUNDLE_FOO" => "bar" }, "ruby -I#{lib} -rbundler -e '#{code}'")
      expect($?.exitstatus).to eq(1)
    end
  end

  describe "Bundler.unbundled_exec" do
    let(:code) do
      <<~RUBY
        Process.fork do
          exit Bundler.unbundled_exec(%(test "\$BUNDLE_FOO" = "bar"))
        end

        _, status = Process.wait2

        exit(status.exitstatus)
      RUBY
    end

    it "runs exec inside with_clean_env" do
      lib = File.expand_path("../../lib", __dir__)
      system({ "BUNDLE_FOO" => "bar" }, "ruby -I#{lib} -rbundler -e '#{code}'")
      expect($?.exitstatus).to eq(1)
    end
  end
end
