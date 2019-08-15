# frozen_string_literal: true

RSpec.describe "bundle exec" do
  let(:system_gems_to_install) { %w[rack-1.0.0 rack-0.9.1] }
  before :each do
    system_gems(system_gems_to_install, :path => :bundle_path)
  end

  it "works with --gemfile flag" do
    create_file "CustomGemfile", <<-G
      gem "rack", "1.0.0"
    G

    bundle "exec --gemfile CustomGemfile rackup"
    expect(out).to eq("1.0.0")
  end

  it "activates the correct gem" do
    gemfile <<-G
      gem "rack", "0.9.1"
    G

    bundle "exec rackup"
    expect(out).to eq("0.9.1")
  end

  it "works when the bins are in ~/.bundle" do
    install_gemfile <<-G
      gem "rack"
    G

    bundle "exec rackup"
    expect(out).to eq("1.0.0")
  end

  it "works when running from a random directory", :ruby_repo do
    install_gemfile <<-G
      gem "rack"
    G

    bundle "exec 'cd #{tmp("gems")} && rackup'"

    expect(out).to eq("1.0.0")
  end

  it "works when exec'ing something else" do
    install_gemfile 'gem "rack"'
    bundle "exec echo exec"
    expect(out).to eq("exec")
  end

  it "works when exec'ing to ruby" do
    install_gemfile 'gem "rack"'
    bundle "exec ruby -e 'puts %{hi}'"
    expect(out).to eq("hi")
  end

  it "respects custom process title when loading through ruby", :github_action_linux do
    script_that_changes_its_own_title_and_checks_if_picked_up_by_ps_unix_utility = <<~RUBY
      Process.setproctitle("1-2-3-4-5-6-7-8-9-10-11-12-13-14-15-16")
      puts `ps -eo args | grep [1]-2-3-4-5-6-7-8-9-10-11-12-13-14-15-16`
    RUBY
    create_file "Gemfile"
    create_file "a.rb", script_that_changes_its_own_title_and_checks_if_picked_up_by_ps_unix_utility
    bundle "exec ruby a.rb"
    expect(out).to eq("1-2-3-4-5-6-7-8-9-10-11-12-13-14-15-16")
  end

  it "accepts --verbose" do
    install_gemfile 'gem "rack"'
    bundle "exec --verbose echo foobar"
    expect(out).to eq("foobar")
  end

  it "passes --verbose to command if it is given after the command" do
    install_gemfile 'gem "rack"'
    bundle "exec echo --verbose"
    expect(out).to eq("--verbose")
  end

  it "handles --keep-file-descriptors" do
    require "tempfile"

    command = Tempfile.new("io-test")
    command.sync = true
    command.write <<-G
      if ARGV[0]
        IO.for_fd(ARGV[0].to_i)
      else
        require 'tempfile'
        io = Tempfile.new("io-test-fd")
        args = %W[#{Gem.ruby} -I#{lib} #{bindir.join("bundle")} exec --keep-file-descriptors #{Gem.ruby} #{command.path} \#{io.to_i}]
        args << { io.to_i => io }
        exec(*args)
      end
    G

    install_gemfile ""
    sys_exec "#{Gem.ruby} #{command.path}"

    expect(out).to eq("")
    expect(err).to be_empty
  end

  it "accepts --keep-file-descriptors" do
    install_gemfile ""
    bundle "exec --keep-file-descriptors echo foobar"

    expect(err).to be_empty
  end

  it "can run a command named --verbose" do
    install_gemfile 'gem "rack"'
    File.open("--verbose", "w") do |f|
      f.puts "#!/bin/sh"
      f.puts "echo foobar"
    end
    File.chmod(0o744, "--verbose")
    with_path_as(".") do
      bundle "exec -- --verbose"
    end
    expect(out).to eq("foobar")
  end

  it "handles different versions in different bundles" do
    build_repo2 do
      build_gem "rack_two", "1.0.0" do |s|
        s.executables = "rackup"
      end
    end

    install_gemfile <<-G
      source "#{file_uri_for(gem_repo1)}"
      gem "rack", "0.9.1"
    G

    Dir.chdir bundled_app2 do
      install_gemfile bundled_app2("Gemfile"), <<-G
        source "#{file_uri_for(gem_repo2)}"
        gem "rack_two", "1.0.0"
      G
    end

    bundle! "exec rackup"

    expect(out).to eq("0.9.1")

    Dir.chdir bundled_app2 do
      bundle! "exec rackup"
      expect(out).to eq("1.0.0")
    end
  end

  context "with default gems" do
    let(:system_gems_to_install) { [] }

    let(:default_irb_version) { ruby "gem 'irb', '< 999999'; require 'irb'; puts IRB::VERSION" }

    context "when not specified in Gemfile" do
      before do
        skip "irb isn't a default gem" if default_irb_version.empty?

        install_gemfile ""
      end

      it "uses version provided by ruby" do
        bundle! "exec irb --version"

        expect(out).to include(default_irb_version)
        expect(err).to be_empty
      end
    end

    context "when specified in Gemfile directly" do
      let(:specified_irb_version) { "0.9.6" }

      before do
        skip "irb isn't a default gem" if default_irb_version.empty?

        build_repo2 do
          build_gem "irb", specified_irb_version do |s|
            s.executables = "irb"
          end
        end

        install_gemfile <<-G
          source "#{file_uri_for(gem_repo2)}"
          gem "irb", "#{specified_irb_version}"
        G
      end

      it "uses version specified" do
        bundle! "exec irb --version"

        expect(out).to include(specified_irb_version)
        expect(err).to be_empty
      end
    end

    context "when specified in Gemfile indirectly" do
      let(:indirect_irb_version) { "0.9.6" }

      before do
        skip "irb isn't a default gem" if default_irb_version.empty?

        build_repo2 do
          build_gem "irb", indirect_irb_version do |s|
            s.executables = "irb"
          end

          build_gem "gem_depending_on_old_irb" do |s|
            s.add_dependency "irb", indirect_irb_version
          end
        end

        install_gemfile <<-G
          source "#{file_uri_for(gem_repo2)}"
          gem "gem_depending_on_old_irb"
        G

        bundle! "exec irb --version"
      end

      it "uses resolved version" do
        expect(out).to include(indirect_irb_version)
        expect(err).to be_empty
      end
    end
  end

  it "warns about executable conflicts" do
    build_repo2 do
      build_gem "rack_two", "1.0.0" do |s|
        s.executables = "rackup"
      end
    end

    bundle "config set path.system true"

    install_gemfile <<-G
      source "#{file_uri_for(gem_repo1)}"
      gem "rack", "0.9.1"
    G

    Dir.chdir bundled_app2 do
      install_gemfile bundled_app2("Gemfile"), <<-G
        source "#{file_uri_for(gem_repo2)}"
        gem "rack_two", "1.0.0"
      G
    end

    bundle! "exec rackup"

    expect(last_command.stderr).to eq(
      "Bundler is using a binstub that was created for a different gem (rack).\n" \
      "You should run `bundle binstub rack_two` to work around a system/bundle conflict."
    )
  end

  it "handles gems installed with --without" do
    install_gemfile <<-G, forgotten_command_line_options(:without => "middleware")
      source "#{file_uri_for(gem_repo1)}"
      gem "rack" # rack 0.9.1 and 1.0 exist

      group :middleware do
        gem "rack_middleware" # rack_middleware depends on rack 0.9.1
      end
    G

    bundle "exec rackup"

    expect(out).to eq("0.9.1")
    expect(the_bundle).not_to include_gems "rack_middleware 1.0"
  end

  it "does not duplicate already exec'ed RUBYOPT" do
    install_gemfile <<-G
      gem "rack"
    G

    rubyopt = ENV["RUBYOPT"]
    setup_path = if ruby_core?
      File.expand_path("../../../lib/bundler/setup", __dir__)
    else
      File.expand_path("../../lib/bundler/setup", __dir__)
    end
    rubyopt = "-r#{setup_path} #{rubyopt}"

    bundle "exec 'echo $RUBYOPT'"
    expect(out).to have_rubyopts(rubyopt)

    bundle "exec 'echo $RUBYOPT'", :env => { "RUBYOPT" => rubyopt }
    expect(out).to have_rubyopts(rubyopt)
  end

  it "does not duplicate already exec'ed RUBYLIB" do
    install_gemfile <<-G
      gem "rack"
    G

    rubylib = ENV["RUBYLIB"]
    rubylib = rubylib.to_s.split(File::PATH_SEPARATOR).unshift bundler_path.to_s
    rubylib = rubylib.uniq.join(File::PATH_SEPARATOR)

    bundle "exec 'echo $RUBYLIB'"
    expect(out).to include(rubylib)

    bundle "exec 'echo $RUBYLIB'", :env => { "RUBYLIB" => rubylib }
    expect(out).to include(rubylib)
  end

  it "errors nicely when the argument doesn't exist" do
    install_gemfile <<-G
      gem "rack"
    G

    bundle "exec foobarbaz"
    expect(exitstatus).to eq(127) if exitstatus
    expect(err).to include("bundler: command not found: foobarbaz")
    expect(err).to include("Install missing gem executables with `bundle install`")
  end

  it "errors nicely when the argument is not executable" do
    install_gemfile <<-G
      gem "rack"
    G

    bundle "exec touch foo"
    bundle "exec ./foo"
    expect(exitstatus).to eq(126) if exitstatus
    expect(err).to include("bundler: not executable: ./foo")
  end

  it "errors nicely when no arguments are passed" do
    install_gemfile <<-G
      gem "rack"
    G

    bundle "exec"
    expect(exitstatus).to eq(128) if exitstatus
    expect(err).to include("bundler: exec needs a command to run")
  end

  it "raises a helpful error when exec'ing to something outside of the bundle", :ruby_repo do
    bundle! "config set clean false" # want to keep the rackup binstub
    install_gemfile! <<-G
      source "#{file_uri_for(gem_repo1)}"
      gem "with_license"
    G
    [true, false].each do |l|
      bundle! "config set disable_exec_load #{l}"
      bundle "exec rackup"
      expect(err).to include "can't find executable rackup for gem rack. rack is not currently included in the bundle, perhaps you meant to add it to your Gemfile?"
    end
  end

  describe "with help flags" do
    each_prefix = proc do |string, &blk|
      1.upto(string.length) {|l| blk.call(string[0, l]) }
    end
    each_prefix.call("exec") do |exec|
      describe "when #{exec} is used" do
        before(:each) do
          install_gemfile <<-G
            gem "rack"
          G

          create_file("print_args", <<-'RUBY')
            #!/usr/bin/env ruby
            puts "args: #{ARGV.inspect}"
          RUBY
          bundled_app("print_args").chmod(0o755)
        end

        it "shows executable's man page when --help is after the executable" do
          bundle "#{exec} print_args --help"
          expect(out).to eq('args: ["--help"]')
        end

        it "shows executable's man page when --help is after the executable and an argument" do
          bundle "#{exec} print_args foo --help"
          expect(out).to eq('args: ["foo", "--help"]')

          bundle "#{exec} print_args foo bar --help"
          expect(out).to eq('args: ["foo", "bar", "--help"]')

          bundle "#{exec} print_args foo --help bar"
          expect(out).to eq('args: ["foo", "--help", "bar"]')
        end

        it "shows executable's man page when the executable has a -" do
          FileUtils.mv(bundled_app("print_args"), bundled_app("docker-template"))
          bundle "#{exec} docker-template build discourse --help"
          expect(out).to eq('args: ["build", "discourse", "--help"]')
        end

        it "shows executable's man page when --help is after another flag" do
          bundle "#{exec} print_args --bar --help"
          expect(out).to eq('args: ["--bar", "--help"]')
        end

        it "uses executable's original behavior for -h" do
          bundle "#{exec} print_args -h"
          expect(out).to eq('args: ["-h"]')
        end

        it "shows bundle-exec's man page when --help is between exec and the executable" do
          with_fake_man do
            bundle "#{exec} --help cat"
          end
          expect(out).to include(%(["#{root}/man/bundle-exec.1"]))
        end

        it "shows bundle-exec's man page when --help is before exec" do
          with_fake_man do
            bundle "--help #{exec}"
          end
          expect(out).to include(%(["#{root}/man/bundle-exec.1"]))
        end

        it "shows bundle-exec's man page when -h is before exec" do
          with_fake_man do
            bundle "-h #{exec}"
          end
          expect(out).to include(%(["#{root}/man/bundle-exec.1"]))
        end

        it "shows bundle-exec's man page when --help is after exec" do
          with_fake_man do
            bundle "#{exec} --help"
          end
          expect(out).to include(%(["#{root}/man/bundle-exec.1"]))
        end

        it "shows bundle-exec's man page when -h is after exec" do
          with_fake_man do
            bundle "#{exec} -h"
          end
          expect(out).to include(%(["#{root}/man/bundle-exec.1"]))
        end
      end
    end
  end

  describe "with gem executables" do
    describe "run from a random directory", :ruby_repo do
      before(:each) do
        install_gemfile <<-G
          gem "rack"
        G
      end

      it "works when unlocked" do
        bundle "exec 'cd #{tmp("gems")} && rackup'"
        expect(out).to eq("1.0.0")
      end

      it "works when locked" do
        expect(the_bundle).to be_locked
        bundle "exec 'cd #{tmp("gems")} && rackup'"
        expect(out).to eq("1.0.0")
      end
    end

    describe "from gems bundled via :path" do
      before(:each) do
        build_lib "fizz", :path => home("fizz") do |s|
          s.executables = "fizz"
        end

        install_gemfile <<-G
          gem "fizz", :path => "#{File.expand_path(home("fizz"))}"
        G
      end

      it "works when unlocked" do
        bundle "exec fizz"
        expect(out).to eq("1.0")
      end

      it "works when locked" do
        expect(the_bundle).to be_locked

        bundle "exec fizz"
        expect(out).to eq("1.0")
      end
    end

    describe "from gems bundled via :git" do
      before(:each) do
        build_git "fizz_git" do |s|
          s.executables = "fizz_git"
        end

        install_gemfile <<-G
          gem "fizz_git", :git => "#{lib_path("fizz_git-1.0")}"
        G
      end

      it "works when unlocked" do
        bundle "exec fizz_git"
        expect(out).to eq("1.0")
      end

      it "works when locked" do
        expect(the_bundle).to be_locked
        bundle "exec fizz_git"
        expect(out).to eq("1.0")
      end
    end

    describe "from gems bundled via :git with no gemspec" do
      before(:each) do
        build_git "fizz_no_gemspec", :gemspec => false do |s|
          s.executables = "fizz_no_gemspec"
        end

        install_gemfile <<-G
          gem "fizz_no_gemspec", "1.0", :git => "#{lib_path("fizz_no_gemspec-1.0")}"
        G
      end

      it "works when unlocked" do
        bundle "exec fizz_no_gemspec"
        expect(out).to eq("1.0")
      end

      it "works when locked" do
        expect(the_bundle).to be_locked
        bundle "exec fizz_no_gemspec"
        expect(out).to eq("1.0")
      end
    end
  end

  it "performs an automatic bundle install" do
    gemfile <<-G
      source "#{file_uri_for(gem_repo1)}"
      gem "rack", "0.9.1"
      gem "foo"
    G

    bundle "config set auto_install 1"
    bundle "exec rackup"
    expect(out).to include("Installing foo 1.0")
  end

  describe "with gems bundled via :path with invalid gemspecs" do
    it "outputs the gemspec validation errors" do
      build_lib "foo"

      gemspec = lib_path("foo-1.0").join("foo.gemspec").to_s
      File.open(gemspec, "w") do |f|
        f.write <<-G
          Gem::Specification.new do |s|
            s.name    = 'foo'
            s.version = '1.0'
            s.summary = 'TODO: Add summary'
            s.authors = 'Me'
          end
        G
      end

      install_gemfile <<-G
        gem "foo", :path => "#{lib_path("foo-1.0")}"
      G

      bundle "exec irb"

      expect(err).to match("The gemspec at #{lib_path("foo-1.0").join("foo.gemspec")} is not valid")
      expect(err).to match('"TODO" is not a summary')
    end
  end

  describe "with gems bundled for deployment" do
    it "works when calling bundler from another script" do
      gemfile <<-G
      module Monkey
        def bin_path(a,b,c)
          raise Gem::GemNotFoundException.new('Fail')
        end
      end
      Bundler.rubygems.extend(Monkey)
      G
      bundle "install --deployment"
      bundle "exec ruby -e '`#{bindir.join("bundler")} -v`; puts $?.success?'"
      expect(out).to match("true")
    end
  end

  context "`load`ing a ruby file instead of `exec`ing" do
    let(:path) { bundled_app("ruby_executable") }
    let(:shebang) { "#!/usr/bin/env ruby" }
    let(:executable) { <<-RUBY.gsub(/^ */, "").strip }
      #{shebang}

      require "rack"
      puts "EXEC: \#{caller.grep(/load/).empty? ? 'exec' : 'load'}"
      puts "ARGS: \#{$0} \#{ARGV.join(' ')}"
      puts "RACK: \#{RACK}"
      process_title = `ps -o args -p \#{Process.pid}`.split("\n", 2).last.strip
      puts "PROCESS: \#{process_title}"
    RUBY

    before do
      path.open("w") {|f| f << executable }
      path.chmod(0o755)

      install_gemfile <<-G
        gem "rack"
      G
    end

    let(:exec) { "EXEC: load" }
    let(:args) { "ARGS: #{path} arg1 arg2" }
    let(:rack) { "RACK: 1.0.0" }
    let(:process) do
      title = "PROCESS: #{path}"
      title += " arg1 arg2"
      title
    end
    let(:exit_code) { 0 }
    let(:expected) { [exec, args, rack, process].join("\n") }
    let(:expected_err) { "" }

    subject { bundle "exec #{path} arg1 arg2" }

    shared_examples_for "it runs" do
      it "like a normally executed executable" do
        subject
        expect(exitstatus).to eq(exit_code) if exitstatus
        expect(err).to eq(expected_err)
        expect(out).to eq(expected)
      end
    end

    it_behaves_like "it runs"

    context "the executable exits explicitly" do
      let(:executable) { super() << "\nexit #{exit_code}\nputs 'POST_EXIT'\n" }

      context "with exit 0" do
        it_behaves_like "it runs"
      end

      context "with exit 99" do
        let(:exit_code) { 99 }
        it_behaves_like "it runs"
      end
    end

    context "the executable exits by SignalException" do
      let(:executable) do
        ex = super()
        ex << "\n"
        ex << "raise SignalException, 'SIGTERM'\n"
        ex
      end
      let(:expected_err) { "" }
      let(:exit_code) do
        # signal mask 128 + plus signal 15 -> TERM
        # this is specified by C99
        128 + 15
      end
      it_behaves_like "it runs"
    end

    context "the executable is empty" do
      let(:executable) { "" }

      let(:exit_code) { 0 }
      let(:expected_err) { "#{path} is empty" }
      let(:expected) { "" }
      it_behaves_like "it runs"
    end

    context "the executable raises" do
      let(:executable) { super() << "\nraise 'ERROR'" }
      let(:exit_code) { 1 }
      let(:expected_err) do
        "bundler: failed to load command: #{path} (#{path})" \
        "\nRuntimeError: ERROR\n  #{path}:10:in `<top (required)>'"
      end
      it_behaves_like "it runs"
    end

    context "the executable raises an error without a backtrace" do
      let(:executable) { super() << "\nclass Err < Exception\ndef backtrace; end;\nend\nraise Err" }
      let(:exit_code) { 1 }
      let(:expected_err) { "bundler: failed to load command: #{path} (#{path})\nErr: Err" }
      let(:expected) { super() }

      it_behaves_like "it runs"
    end

    context "when the file uses the current ruby shebang", :ruby_repo do
      let(:shebang) { "#!#{Gem.ruby}" }
      it_behaves_like "it runs"
    end

    context "when Bundler.setup fails", :bundler => "< 3" do
      before do
        gemfile <<-G
          gem 'rack', '2'
        G
        ENV["BUNDLER_FORCE_TTY"] = "true"
      end

      let(:exit_code) { Bundler::GemNotFound.new.status_code }
      let(:expected) { "" }
      let(:expected_err) { <<-EOS.strip }
\e[31mCould not find gem 'rack (= 2)' in any of the gem sources listed in your Gemfile.\e[0m
\e[33mRun `bundle install` to install missing gems.\e[0m
      EOS

      it_behaves_like "it runs"
    end

    context "when Bundler.setup fails", :bundler => "3" do
      before do
        gemfile <<-G
          gem 'rack', '2'
        G
        ENV["BUNDLER_FORCE_TTY"] = "true"
      end

      let(:exit_code) { Bundler::GemNotFound.new.status_code }
      let(:expected) { "" }
      let(:expected_err) { <<-EOS.strip }
\e[31mCould not find gem 'rack (= 2)' in locally installed gems.
The source contains 'rack' at: 1.0.0\e[0m
\e[33mRun `bundle install` to install missing gems.\e[0m
      EOS

      it_behaves_like "it runs"
    end

    context "when the executable exits non-zero via at_exit" do
      let(:executable) { super() + "\n\nat_exit { $! ? raise($!) : exit(1) }" }
      let(:exit_code) { 1 }

      it_behaves_like "it runs"
    end

    context "when disable_exec_load is set" do
      let(:exec) { "EXEC: exec" }
      let(:process) { "PROCESS: ruby #{path} arg1 arg2" }

      before do
        bundle "config set disable_exec_load true"
      end

      it_behaves_like "it runs"
    end

    context "regarding $0 and __FILE__" do
      let(:executable) { super() + <<-'RUBY' }

        puts "$0: #{$0.inspect}"
        puts "__FILE__: #{__FILE__.inspect}"
      RUBY

      let(:expected) { super() + <<-EOS.chomp }

$0: #{path.to_s.inspect}
__FILE__: #{path.to_s.inspect}
      EOS

      it_behaves_like "it runs"

      context "when the path is relative" do
        let(:path) { super().relative_path_from(bundled_app) }

        it_behaves_like "it runs"
      end

      context "when the path is relative with a leading ./" do
        let(:path) { Pathname.new("./#{super().relative_path_from(Pathname.pwd)}") }

        pending "relative paths with ./ have absolute __FILE__"
      end
    end

    context "signal handling" do
      let(:test_signals) do
        open3_reserved_signals = %w[CHLD CLD PIPE]
        reserved_signals = %w[SEGV BUS ILL FPE VTALRM KILL STOP EXIT]
        bundler_signals = %w[INT]

        Signal.list.keys - (bundler_signals + reserved_signals + open3_reserved_signals)
      end

      context "signals being trapped by bundler" do
        let(:executable) { strip_whitespace <<-RUBY }
          #{shebang}
          begin
            Thread.new do
              puts 'Started' # For process sync
              STDOUT.flush
              sleep 1 # ignore quality_spec
              raise "Didn't receive INT at all"
            end.join
          rescue Interrupt
            puts "foo"
          end
        RUBY

        it "receives the signal" do
          bundle!("exec #{path}") do |_, o, thr|
            o.gets # Consumes 'Started' and ensures that thread has started
            Process.kill("INT", thr.pid)
          end

          expect(out).to eq("foo")
        end
      end

      context "signals not being trapped by bunder" do
        let(:executable) { strip_whitespace <<-RUBY }
          #{shebang}

          signals = #{test_signals.inspect}
          result = signals.map do |sig|
            Signal.trap(sig, "IGNORE")
          end
          puts result.select { |ret| ret == "IGNORE" }.count
        RUBY

        it "makes sure no unexpected signals are restored to DEFAULT" do
          test_signals.each do |n|
            Signal.trap(n, "IGNORE")
          end

          bundle!("exec #{path}")

          expect(out).to eq(test_signals.count.to_s)
        end
      end
    end
  end

  context "nested bundle exec" do
    let(:system_gems_to_install) { super() << :bundler }

    context "with shared gems disabled" do
      before do
        gemfile <<-G
          source "#{file_uri_for(gem_repo1)}"
          gem "rack"
        G
        bundle :install, :system_bundler => true, :path => "vendor/bundler"
      end

      it "overrides disable_shared_gems so bundler can be found", :ruby_repo do
        system_gems :bundler
        file = bundled_app("file_that_bundle_execs.rb")
        create_file(file, <<-RB)
          #!#{Gem.ruby}
          puts `#{system_bundle_bin_path} exec echo foo`
        RB
        file.chmod(0o777)
        bundle! "exec #{file}", :system_bundler => true
        expect(out).to eq("foo")
      end
    end

    context "with a system gem that shadows a default gem" do
      let(:openssl_version) { "99.9.9" }
      let(:expected) { ruby "gem 'openssl', '< 999999'; require 'openssl'; puts OpenSSL::VERSION", :artifice => nil }

      it "only leaves the default gem in the stdlib available" do
        skip "openssl isn't a default gem" if expected.empty?

        install_gemfile! "" # must happen before installing the broken system gem

        build_repo4 do
          build_gem "openssl", openssl_version do |s|
            s.write("lib/openssl.rb", <<-RB)
              raise "custom openssl should not be loaded, it's not in the gemfile!"
            RB
          end
        end

        system_gems(:bundler, "openssl-#{openssl_version}", :gem_repo => gem_repo4)

        file = bundled_app("require_openssl.rb")
        create_file(file, <<-RB)
          #!/usr/bin/env ruby
          require "openssl"
          puts OpenSSL::VERSION
          warn Gem.loaded_specs.values.map(&:full_name)
        RB
        file.chmod(0o777)

        aggregate_failures do
          expect(bundle!("exec #{file}", :artifice => nil)).to eq(expected)
          expect(bundle!("exec bundle exec #{file}", :artifice => nil)).to eq(expected)
          expect(bundle!("exec ruby #{file}", :artifice => nil)).to eq(expected)
          expect(run!(file.read, :artifice => nil)).to eq(expected)
        end

        # sanity check that we get the newer, custom version without bundler
        sys_exec("#{Gem.ruby} #{file}")
        expect(err).to include("custom openssl should not be loaded")
      end
    end
  end
end
