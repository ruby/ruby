require 'reline'

begin
  require 'yamatanooroti'

  class Reline::TestRendering < Yamatanooroti::TestCase
    def setup
      @pwd = Dir.pwd
      @tmpdir = File.join(Dir.tmpdir, "test_reline_config_#{$$}")
      begin
        Dir.mkdir(@tmpdir)
      rescue Errno::EEXIST
        FileUtils.rm_rf(@tmpdir)
        Dir.mkdir(@tmpdir)
      end
      Dir.chdir(@tmpdir)
      inputrc_backup = ENV['INPUTRC']
      @inputrc_file = ENV['INPUTRC'] = File.expand_path('temporaty_inputrc')
      File.unlink(@inputrc_file) if File.exist?(@inputrc_file)
      start_terminal(5, 30, %W{ruby -I#{@pwd}/lib #{@pwd}/bin/multiline_repl})
      sleep 0.5
      ENV['INPUTRC'] = inputrc_backup
    end

    def teardown
      Dir.chdir(@pwd)
      FileUtils.rm_rf(@tmpdir)
    end

    def test_history_back
      write(":a\n")
      write("\C-p")
      close
      assert_screen(<<~EOC)
        Multiline REPL.
        prompt> :a
        => :a
        prompt> :a
      EOC
    end

    def test_backspace
      write(":abc\C-h\n")
      close
      assert_screen(<<~EOC)
        Multiline REPL.
        prompt> :ab
        => :ab
        prompt>
      EOC
    end

    def test_autowrap
      write('01234567890123456789012')
      close
      assert_screen(<<~EOC)
        Multiline REPL.
        prompt> 0123456789012345678901
        2
      EOC
    end
  end
rescue LoadError, NameError
  # On Ruby repository, this test suit doesn't run because Ruby repo doesn't
  # have the yamatanooroti gem.
end
