# frozen_string_literal: false
require "irb"
require "fileutils"

require_relative "helper"

module TestIRB
  class InitTest < TestCase
    def setup
      # IRBRC is for RVM...
      @backup_env = %w[HOME XDG_CONFIG_HOME IRBRC].each_with_object({}) do |env, hash|
        hash[env] = ENV.delete(env)
      end
      ENV["HOME"] = @tmpdir = File.realpath(Dir.mktmpdir("test_irb_init_#{$$}"))
    end

    def teardown
      ENV.update(@backup_env)
      FileUtils.rm_rf(@tmpdir)
      IRB.conf.delete(:SCRIPT)
    end

    def test_setup_with_argv_preserves_global_argv
      argv = ["foo", "bar"]
      with_argv(argv) do
        IRB.setup(eval("__FILE__"), argv: %w[-f])
        assert_equal argv, ARGV
      end
    end

    def test_setup_with_minimum_argv_does_not_change_dollar0
      orig = $0.dup
      IRB.setup(eval("__FILE__"), argv: %w[-f])
      assert_equal orig, $0
    end

    def test_rc_file
      verbose, $VERBOSE = $VERBOSE, nil
      tmpdir = @tmpdir
      Dir.chdir(tmpdir) do
        ENV["XDG_CONFIG_HOME"] = "#{tmpdir}/xdg"
        IRB.conf[:RC_NAME_GENERATOR] = nil
        assert_equal(tmpdir+"/.irbrc", IRB.rc_file)
        assert_equal(tmpdir+"/.irb_history", IRB.rc_file("_history"))
        assert_file.not_exist?(tmpdir+"/xdg")
        IRB.conf[:RC_NAME_GENERATOR] = nil
        FileUtils.touch(tmpdir+"/.irbrc")
        assert_equal(tmpdir+"/.irbrc", IRB.rc_file)
        assert_equal(tmpdir+"/.irb_history", IRB.rc_file("_history"))
        assert_file.not_exist?(tmpdir+"/xdg")
      end
    ensure
      $VERBOSE = verbose
    end

    def test_rc_file_in_subdir
      verbose, $VERBOSE = $VERBOSE, nil
      tmpdir = @tmpdir
      Dir.chdir(tmpdir) do
        FileUtils.mkdir_p("#{tmpdir}/mydir")
        Dir.chdir("#{tmpdir}/mydir") do
          IRB.conf[:RC_NAME_GENERATOR] = nil
          assert_equal(tmpdir+"/.irbrc", IRB.rc_file)
          assert_equal(tmpdir+"/.irb_history", IRB.rc_file("_history"))
          IRB.conf[:RC_NAME_GENERATOR] = nil
          FileUtils.touch(tmpdir+"/.irbrc")
          assert_equal(tmpdir+"/.irbrc", IRB.rc_file)
          assert_equal(tmpdir+"/.irb_history", IRB.rc_file("_history"))
        end
      end
    ensure
      $VERBOSE = verbose
    end

    def test_rc_files
      tmpdir = @tmpdir
      Dir.chdir(tmpdir) do
        ENV["XDG_CONFIG_HOME"] = "#{tmpdir}/xdg"
        IRB.conf[:RC_NAME_GENERATOR] = nil
        assert_includes IRB.rc_files, tmpdir+"/.irbrc"
        assert_includes IRB.rc_files("_history"), tmpdir+"/.irb_history"
        assert_file.not_exist?(tmpdir+"/xdg")
        IRB.conf[:RC_NAME_GENERATOR] = nil
        FileUtils.touch(tmpdir+"/.irbrc")
        assert_includes IRB.rc_files, tmpdir+"/.irbrc"
        assert_includes IRB.rc_files("_history"), tmpdir+"/.irb_history"
        assert_file.not_exist?(tmpdir+"/xdg")
      end
    end

    def test_rc_files_in_subdir
      tmpdir = @tmpdir
      Dir.chdir(tmpdir) do
        FileUtils.mkdir_p("#{tmpdir}/mydir")
        Dir.chdir("#{tmpdir}/mydir") do
          IRB.conf[:RC_NAME_GENERATOR] = nil
          assert_includes IRB.rc_files, tmpdir+"/.irbrc"
          assert_includes IRB.rc_files("_history"), tmpdir+"/.irb_history"
          IRB.conf[:RC_NAME_GENERATOR] = nil
          FileUtils.touch(tmpdir+"/.irbrc")
          assert_includes IRB.rc_files, tmpdir+"/.irbrc"
          assert_includes IRB.rc_files("_history"), tmpdir+"/.irb_history"
        end
      end
    end

    def test_rc_files_has_file_from_xdg_env
      tmpdir = @tmpdir
      ENV["XDG_CONFIG_HOME"] = "#{tmpdir}/xdg"
      xdg_config = ENV["XDG_CONFIG_HOME"]+"/irb/irbrc"

      FileUtils.mkdir_p(xdg_config)

      Dir.chdir(tmpdir) do
        IRB.conf[:RC_NAME_GENERATOR] = nil
        assert_includes IRB.rc_files, xdg_config
      end
    ensure
      ENV["XDG_CONFIG_HOME"] = nil
    end

    def test_rc_files_has_file_from_irbrc_env
      tmpdir = @tmpdir
      ENV["IRBRC"] = "#{tmpdir}/irb"

      FileUtils.mkdir_p(ENV["IRBRC"])

      Dir.chdir(tmpdir) do
        IRB.conf[:RC_NAME_GENERATOR] = nil
        assert_includes IRB.rc_files, ENV["IRBRC"]
      end
    ensure
      ENV["IRBRC"] = nil
    end

    def test_rc_files_has_file_from_home_env
      tmpdir = @tmpdir
      ENV["HOME"] = "#{tmpdir}/home"

      FileUtils.mkdir_p(ENV["HOME"])

      Dir.chdir(tmpdir) do
        IRB.conf[:RC_NAME_GENERATOR] = nil
        assert_includes IRB.rc_files, ENV["HOME"]+"/.irbrc"
        assert_includes IRB.rc_files, ENV["HOME"]+"/.config/irb/irbrc"
      end
    ensure
      ENV["HOME"] = nil
    end

    def test_rc_files_contains_non_env_files
      tmpdir = @tmpdir
      FileUtils.mkdir_p("#{tmpdir}/.irbrc")
      FileUtils.mkdir_p("#{tmpdir}/_irbrc")
      FileUtils.mkdir_p("#{tmpdir}/irb.rc")
      FileUtils.mkdir_p("#{tmpdir}/$irbrc")

      Dir.chdir(tmpdir) do
        IRB.conf[:RC_NAME_GENERATOR] = nil
        assert_includes IRB.rc_files, tmpdir+"/.irbrc"
        assert_includes IRB.rc_files, tmpdir+"/_irbrc"
        assert_includes IRB.rc_files, tmpdir+"/irb.rc"
        assert_includes IRB.rc_files, tmpdir+"/$irbrc"
      end
    end

    def test_sigint_restore_default
      pend "This test gets stuck on Solaris for unknown reason; contribution is welcome" if RUBY_PLATFORM =~ /solaris/
      bundle_exec = ENV.key?('BUNDLE_GEMFILE') ? ['-rbundler/setup'] : []
      # IRB should restore SIGINT handler
      status = assert_in_out_err(bundle_exec + %w[-W0 -rirb -e Signal.trap("SIGINT","DEFAULT");binding.irb;loop{Process.kill("SIGINT",$$)} -- -f --], "exit\n", //, //)
      Process.kill("SIGKILL", status.pid) if !status.exited? && !status.stopped? && !status.signaled?
    end

    def test_sigint_restore_block
      bundle_exec = ENV.key?('BUNDLE_GEMFILE') ? ['-rbundler/setup'] : []
      # IRB should restore SIGINT handler
      status = assert_in_out_err(bundle_exec + %w[-W0 -rirb -e x=false;Signal.trap("SIGINT"){x=true};binding.irb;loop{Process.kill("SIGINT",$$);if(x);break;end} -- -f --], "exit\n", //, //)
      Process.kill("SIGKILL", status.pid) if !status.exited? && !status.stopped? && !status.signaled?
    end

    def test_no_color_environment_variable
      orig_no_color = ENV['NO_COLOR']
      orig_use_colorize = IRB.conf[:USE_COLORIZE]
      IRB.conf[:USE_COLORIZE] = true

      assert IRB.conf[:USE_COLORIZE]

      ENV['NO_COLOR'] = 'true'
      IRB.setup(__FILE__)
      refute IRB.conf[:USE_COLORIZE]

      ENV['NO_COLOR'] = ''
      IRB.setup(__FILE__)
      assert IRB.conf[:USE_COLORIZE]

      ENV['NO_COLOR'] = nil
      IRB.setup(__FILE__)
      assert IRB.conf[:USE_COLORIZE]
    ensure
      ENV['NO_COLOR'] = orig_no_color
      IRB.conf[:USE_COLORIZE] = orig_use_colorize
    end

    def test_use_autocomplete_environment_variable
      orig_use_autocomplete_env = ENV['IRB_USE_AUTOCOMPLETE']
      orig_use_autocomplete_conf = IRB.conf[:USE_AUTOCOMPLETE]

      ENV['IRB_USE_AUTOCOMPLETE'] = nil
      IRB.setup(__FILE__)
      assert IRB.conf[:USE_AUTOCOMPLETE]

      ENV['IRB_USE_AUTOCOMPLETE'] = ''
      IRB.setup(__FILE__)
      assert IRB.conf[:USE_AUTOCOMPLETE]

      ENV['IRB_USE_AUTOCOMPLETE'] = 'false'
      IRB.setup(__FILE__)
      refute IRB.conf[:USE_AUTOCOMPLETE]

      ENV['IRB_USE_AUTOCOMPLETE'] = 'true'
      IRB.setup(__FILE__)
      assert IRB.conf[:USE_AUTOCOMPLETE]
    ensure
      ENV["IRB_USE_AUTOCOMPLETE"] = orig_use_autocomplete_env
      IRB.conf[:USE_AUTOCOMPLETE] = orig_use_autocomplete_conf
    end

    def test_completor_environment_variable
      orig_use_autocomplete_env = ENV['IRB_COMPLETOR']
      orig_use_autocomplete_conf = IRB.conf[:COMPLETOR]

      ENV['IRB_COMPLETOR'] = nil
      IRB.setup(__FILE__)
      assert_equal(:regexp, IRB.conf[:COMPLETOR])

      ENV['IRB_COMPLETOR'] = 'regexp'
      IRB.setup(__FILE__)
      assert_equal(:regexp, IRB.conf[:COMPLETOR])

      ENV['IRB_COMPLETOR'] = 'type'
      IRB.setup(__FILE__)
      assert_equal(:type, IRB.conf[:COMPLETOR])

      ENV['IRB_COMPLETOR'] = 'regexp'
      IRB.setup(__FILE__, argv: ['--type-completor'])
      assert_equal :type, IRB.conf[:COMPLETOR]

      ENV['IRB_COMPLETOR'] = 'type'
      IRB.setup(__FILE__, argv: ['--regexp-completor'])
      assert_equal :regexp, IRB.conf[:COMPLETOR]
    ensure
      ENV['IRB_COMPLETOR'] = orig_use_autocomplete_env
      IRB.conf[:COMPLETOR] = orig_use_autocomplete_conf
    end

    def test_completor_setup_with_argv
      orig_completor_conf = IRB.conf[:COMPLETOR]

      # Default is :regexp
      IRB.setup(__FILE__, argv: [])
      assert_equal :regexp, IRB.conf[:COMPLETOR]

      IRB.setup(__FILE__, argv: ['--type-completor'])
      assert_equal :type, IRB.conf[:COMPLETOR]

      IRB.setup(__FILE__, argv: ['--regexp-completor'])
      assert_equal :regexp, IRB.conf[:COMPLETOR]
    ensure
      IRB.conf[:COMPLETOR] = orig_completor_conf
    end

    def test_noscript
      argv = %w[--noscript -- -f]
      IRB.setup(eval("__FILE__"), argv: argv)
      assert_nil IRB.conf[:SCRIPT]
      assert_equal(['-f'], argv)

      argv = %w[--noscript -- a]
      IRB.setup(eval("__FILE__"), argv: argv)
      assert_nil IRB.conf[:SCRIPT]
      assert_equal(['a'], argv)

      argv = %w[--noscript a]
      IRB.setup(eval("__FILE__"), argv: argv)
      assert_nil IRB.conf[:SCRIPT]
      assert_equal(['a'], argv)

      argv = %w[--script --noscript a]
      IRB.setup(eval("__FILE__"), argv: argv)
      assert_nil IRB.conf[:SCRIPT]
      assert_equal(['a'], argv)

      argv = %w[--noscript --script a]
      IRB.setup(eval("__FILE__"), argv: argv)
      assert_equal('a', IRB.conf[:SCRIPT])
      assert_equal([], argv)
    end

    def test_dash
      argv = %w[-]
      IRB.setup(eval("__FILE__"), argv: argv)
      assert_equal('-', IRB.conf[:SCRIPT])
      assert_equal([], argv)

      argv = %w[-- -]
      IRB.setup(eval("__FILE__"), argv: argv)
      assert_equal('-', IRB.conf[:SCRIPT])
      assert_equal([], argv)

      argv = %w[-- - -f]
      IRB.setup(eval("__FILE__"), argv: argv)
      assert_equal('-', IRB.conf[:SCRIPT])
      assert_equal(['-f'], argv)
    end

    def test_option_tracer
      argv = %w[--tracer]
      IRB.setup(eval("__FILE__"), argv: argv)
      assert_equal(true, IRB.conf[:USE_TRACER])
    end

    private

    def with_argv(argv)
      orig = ARGV.dup
      ARGV.replace(argv)
      yield
    ensure
      ARGV.replace(orig)
    end
  end

  class InitIntegrationTest < IntegrationTestCase
    def test_load_error_in_rc_file_is_warned
      write_rc <<~'IRBRC'
        require "file_that_does_not_exist"
      IRBRC

      write_ruby <<~'RUBY'
        binding.irb
      RUBY

      output = run_ruby_file do
        type "'foobar'"
        type "exit"
      end

      # IRB session should still be started
      assert_includes output, "foobar"
      assert_includes output, 'cannot load such file -- file_that_does_not_exist (LoadError)'
    end

    def test_normal_errors_in_rc_file_is_warned
      write_rc <<~'IRBRC'
        raise "I'm an error"
      IRBRC

      write_ruby <<~'RUBY'
        binding.irb
      RUBY

      output = run_ruby_file do
        type "'foobar'"
        type "exit"
      end

      # IRB session should still be started
      assert_includes output, "foobar"
      assert_includes output, 'I\'m an error (RuntimeError)'
    end
  end
end
