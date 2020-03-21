require 'reline'

begin
  require 'yamatanooroti'

  class Reline::TestRendering < Yamatanooroti::TestCase
    def setup
      inputrc_backup = ENV['INPUTRC']
      ENV['INPUTRC'] = 'nonexistent_file'
      start_terminal(5, 30, %w{ruby -Ilib bin/multiline_repl})
      sleep 0.5
      ENV['INPUTRC'] = inputrc_backup
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
  end
rescue LoadError, NameError
  # On Ruby repository, this test suit doesn't run because Ruby repo doesn't
  # have the yamatanooroti gem.
end
