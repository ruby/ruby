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

    def reset_rc_name_generators
      IRB.instance_variable_set(:@existing_rc_name_generators, nil)
    end

    def teardown
      ENV.update(@backup_env)
      FileUtils.rm_rf(@tmpdir)
      IRB.conf.delete(:SCRIPT)
      reset_rc_name_generators
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

    def test_rc_files
      tmpdir = @tmpdir
      Dir.chdir(tmpdir) do
        home = ENV['HOME'] = "#{tmpdir}/home"
        xdg_config_home = ENV['XDG_CONFIG_HOME'] = "#{tmpdir}/xdg"
        reset_rc_name_generators
        assert_empty(IRB.irbrc_files)
        assert_equal("#{home}/.irb_history", IRB.rc_file('_history'))
        FileUtils.mkdir_p(home)
        FileUtils.mkdir_p("#{xdg_config_home}/irb")
        FileUtils.mkdir_p("#{home}/.config/irb")
        reset_rc_name_generators
        assert_empty(IRB.irbrc_files)
        assert_equal("#{xdg_config_home}/irb/irb_history", IRB.rc_file('_history'))
        home_irbrc = "#{home}/.irbrc"
        config_irbrc = "#{home}/.config/irb/irbrc"
        xdg_config_irbrc = "#{xdg_config_home}/irb/irbrc"
        [home_irbrc, config_irbrc, xdg_config_irbrc].each do |file|
          FileUtils.touch(file)
        end
        current_dir_irbrcs = %w[.irbrc irbrc _irbrc $irbrc].map { |file| "#{tmpdir}/#{file}" }
        current_dir_irbrcs.each { |file| FileUtils.touch(file) }
        reset_rc_name_generators
        assert_equal([xdg_config_irbrc, home_irbrc, *current_dir_irbrcs], IRB.irbrc_files)
        assert_equal(xdg_config_irbrc.sub(/rc$/, '_history'), IRB.rc_file('_history'))
        ENV['XDG_CONFIG_HOME'] = nil
        reset_rc_name_generators
        assert_equal([home_irbrc, config_irbrc, *current_dir_irbrcs], IRB.irbrc_files)
        assert_equal(home_irbrc.sub(/rc$/, '_history'), IRB.rc_file('_history'))
        ENV['XDG_CONFIG_HOME'] = ''
        reset_rc_name_generators
        assert_equal([home_irbrc, config_irbrc] + current_dir_irbrcs, IRB.irbrc_files)
        assert_equal(home_irbrc.sub(/rc$/, '_history'), IRB.rc_file('_history'))
        ENV['XDG_CONFIG_HOME'] = xdg_config_home
        ENV['IRBRC'] = "#{tmpdir}/.irbrc"
        reset_rc_name_generators
        assert_equal([ENV['IRBRC'], xdg_config_irbrc, home_irbrc] + (current_dir_irbrcs - [ENV['IRBRC']]), IRB.irbrc_files)
        assert_equal(ENV['IRBRC'] + '_history', IRB.rc_file('_history'))
        ENV['IRBRC'] = ENV['HOME'] = ENV['XDG_CONFIG_HOME'] = nil
        reset_rc_name_generators
        assert_equal(current_dir_irbrcs, IRB.irbrc_files)
        assert_nil(IRB.rc_file('_history'))
      end
    end

    def test_duplicated_rc_files
      tmpdir = @tmpdir
      Dir.chdir(tmpdir) do
        ENV['XDG_CONFIG_HOME'] = "#{ENV['HOME']}/.config"
        FileUtils.mkdir_p("#{ENV['XDG_CONFIG_HOME']}/irb")
        env_irbrc = ENV['IRBRC'] = "#{tmpdir}/_irbrc"
        xdg_config_irbrc = "#{ENV['XDG_CONFIG_HOME']}/irb/irbrc"
        home_irbrc = "#{ENV['HOME']}/.irbrc"
        current_dir_irbrc = "#{tmpdir}/irbrc"
        [env_irbrc, xdg_config_irbrc, home_irbrc, current_dir_irbrc].each do |file|
          FileUtils.touch(file)
        end
        reset_rc_name_generators
        assert_equal([env_irbrc, xdg_config_irbrc, home_irbrc, current_dir_irbrc], IRB.irbrc_files)
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

  class ConfigValidationTest < TestCase
    def setup
      @original_home = ENV["HOME"]
      @original_irbrc = ENV["IRBRC"]
      # To prevent the test from using the user's .irbrc file
      ENV["HOME"] = @home = Dir.mktmpdir
      super
    end

    def teardown
      super
      ENV["IRBRC"] = @original_irbrc
      ENV["HOME"] = @original_home
      File.unlink(@irbrc)
      Dir.rmdir(@home)
      IRB.instance_variable_set(:@existing_rc_name_generators, nil)
    end

    def test_irb_name_converts_non_string_values_to_string
      assert_no_irb_validation_error(<<~'RUBY')
        IRB.conf[:IRB_NAME] = :foo
      RUBY

      assert_equal "foo", IRB.conf[:IRB_NAME]
    end

    def test_irb_rc_name_only_takes_callable_objects
      assert_irb_validation_error(<<~'RUBY', "IRB.conf[:IRB_RC] should be a callable object. Got :foo.")
        IRB.conf[:IRB_RC] = :foo
      RUBY
    end

    def test_back_trace_limit_only_accepts_integers
      assert_irb_validation_error(<<~'RUBY', "IRB.conf[:BACK_TRACE_LIMIT] should be an integer. Got \"foo\".")
        IRB.conf[:BACK_TRACE_LIMIT] = "foo"
      RUBY
    end

    def test_prompt_only_accepts_hash
      assert_irb_validation_error(<<~'RUBY', "IRB.conf[:PROMPT] should be a Hash. Got \"foo\".")
        IRB.conf[:PROMPT] = "foo"
      RUBY
    end

    def test_eval_history_only_accepts_integers
      assert_irb_validation_error(<<~'RUBY', "IRB.conf[:EVAL_HISTORY] should be an integer. Got \"foo\".")
        IRB.conf[:EVAL_HISTORY] = "foo"
      RUBY
    end

    private

    def assert_irb_validation_error(rc_content, error_message)
      write_rc rc_content

      assert_raise_with_message(TypeError, error_message) do
        IRB.setup(__FILE__)
      end
    end

    def assert_no_irb_validation_error(rc_content)
      write_rc rc_content

      assert_nothing_raised do
        IRB.setup(__FILE__)
      end
    end

    def write_rc(content)
      @irbrc = Tempfile.new('irbrc')
      @irbrc.write(content)
      @irbrc.close
      ENV['IRBRC'] = @irbrc.path
    end
  end

  class InitIntegrationTest < IntegrationTestCase
    def setup
      super

      write_ruby <<~'RUBY'
        binding.irb
      RUBY
    end

    def test_load_error_in_rc_file_is_warned
      write_rc <<~'IRBRC'
        require "file_that_does_not_exist"
      IRBRC

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
