require 'reline'

begin
  require 'yamatanooroti'

  class Reline::TestRendering < Yamatanooroti::TestCase
    def setup
      @pwd = Dir.pwd
      @tmpdir = File.join(File.expand_path(Dir.tmpdir), "test_reline_config_#{$$}")
      begin
        Dir.mkdir(@tmpdir)
      rescue Errno::EEXIST
        FileUtils.rm_rf(@tmpdir)
        Dir.mkdir(@tmpdir)
      end
      Dir.chdir(@tmpdir)
      @inputrc_backup = ENV['INPUTRC']
      @inputrc_file = ENV['INPUTRC'] = File.join(@tmpdir, 'temporaty_inputrc')
      File.unlink(@inputrc_file) if File.exist?(@inputrc_file)
    end

    def teardown
      Dir.chdir(@pwd)
      FileUtils.rm_rf(@tmpdir)
      ENV['INPUTRC'] = @inputrc_backup
    end

    def test_history_back
      start_terminal(5, 30, %W{ruby -I#{@pwd}/lib #{@pwd}/bin/multiline_repl})
      sleep 0.5
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
      start_terminal(5, 30, %W{ruby -I#{@pwd}/lib #{@pwd}/bin/multiline_repl})
      sleep 0.5
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
      start_terminal(5, 30, %W{ruby -I#{@pwd}/lib #{@pwd}/bin/multiline_repl})
      sleep 0.5
      write('01234567890123456789012')
      close
      assert_screen(<<~EOC)
        Multiline REPL.
        prompt> 0123456789012345678901
        2
      EOC
    end

    def test_prompt
      File.open(@inputrc_file, 'w') do |f|
        f.write <<~'LINES'
          "abc": "123"
        LINES
      end
      start_terminal(5, 30, %W{ruby -I#{@pwd}/lib #{@pwd}/bin/multiline_repl})
      sleep 0.5
      write("abc\n")
      close
      assert_screen(<<~EOC)
        Multiline REPL.
        prompt> 123
        => 123
        prompt>
      EOC
    end

    def test_mode_icon_emacs
      File.open(@inputrc_file, 'w') do |f|
        f.write <<~LINES
          set show-mode-in-prompt on
        LINES
      end
      start_terminal(5, 30, %W{ruby -I#{@pwd}/lib #{@pwd}/bin/multiline_repl})
      sleep 0.5
      close
      assert_screen(<<~EOC)
        Multiline REPL.
        @prompt>
      EOC
    end

    def test_mode_icon_vi
      File.open(@inputrc_file, 'w') do |f|
        f.write <<~LINES
          set editing-mode vi
          set show-mode-in-prompt on
        LINES
      end
      start_terminal(5, 30, %W{ruby -I#{@pwd}/lib #{@pwd}/bin/multiline_repl})
      sleep 0.5
      write(":a\n\C-[k")
      close
      assert_screen(<<~EOC)
        Multiline REPL.
        (ins)prompt> :a
        => :a
        (cmd)prompt> :a
      EOC
    end
  end
rescue LoadError, NameError
  # On Ruby repository, this test suit doesn't run because Ruby repo doesn't
  # have the yamatanooroti gem.
end
