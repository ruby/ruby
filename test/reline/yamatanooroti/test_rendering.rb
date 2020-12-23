require 'reline'

begin
  require 'yamatanooroti'

  class Reline::TestRendering < Yamatanooroti::TestCase
    def setup
      @pwd = Dir.pwd
      suffix = '%010d' % Random.rand(0..65535)
      @tmpdir = File.join(File.expand_path(Dir.tmpdir), "test_reline_config_#{$$}_#{suffix}")
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
      ENV.delete('RELINE_TEST_PROMPT') if ENV['RELINE_TEST_PROMPT']
    end

    def test_history_back
      start_terminal(5, 30, %W{ruby -I#{@pwd}/lib #{@pwd}/bin/multiline_repl}, startup_message: 'Multiline REPL.')
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
      start_terminal(5, 30, %W{ruby -I#{@pwd}/lib #{@pwd}/bin/multiline_repl}, startup_message: 'Multiline REPL.')
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
      start_terminal(5, 30, %W{ruby -I#{@pwd}/lib #{@pwd}/bin/multiline_repl}, startup_message: 'Multiline REPL.')
      write('01234567890123456789012')
      close
      assert_screen(<<~EOC)
        Multiline REPL.
        prompt> 0123456789012345678901
        2
      EOC
    end

    def test_fullwidth
      start_terminal(5, 30, %W{ruby -I#{@pwd}/lib #{@pwd}/bin/multiline_repl}, startup_message: 'Multiline REPL.')
      write(":あ\n")
      close
      assert_screen(<<~EOC)
        Multiline REPL.
        prompt> :あ
        => :あ
        prompt>
      EOC
    end

    def test_two_fullwidth
      start_terminal(5, 30, %W{ruby -I#{@pwd}/lib #{@pwd}/bin/multiline_repl}, startup_message: 'Multiline REPL.')
      write(":あい\n")
      close
      assert_screen(<<~EOC)
        Multiline REPL.
        prompt> :あい
        => :あい
        prompt>
      EOC
    end

    def test_finish_autowrapped_line
      start_terminal(10, 40, %W{ruby -I#{@pwd}/lib #{@pwd}/bin/multiline_repl}, startup_message: 'Multiline REPL.')
      write("[{'user'=>{'email'=>'a@a', 'id'=>'ABC'}, 'version'=>4, 'status'=>'succeeded'}]\n")
      close
      assert_screen(<<~EOC)
        Multiline REPL.
        prompt> [{'user'=>{'email'=>'a@a', 'id'=
        >'ABC'}, 'version'=>4, 'status'=>'succee
        ded'}]
        => [{"user"=>{"email"=>"a@a", "id"=>"ABC
        "}, "version"=>4, "status"=>"succeeded"}
        ]
        prompt>
      EOC
    end

    def test_finish_autowrapped_line_in_the_middle_of_lines
      start_terminal(20, 30, %W{ruby -I#{@pwd}/lib #{@pwd}/bin/multiline_repl}, startup_message: 'Multiline REPL.')
      write("[{'user'=>{'email'=>'abcdef@abcdef', 'id'=>'ABC'}, 'version'=>4, 'status'=>'succeeded'}]#{"\C-b"*7}")
      write("\n")
      close
      assert_screen(<<~EOC)
        Multiline REPL.
        prompt> [{'user'=>{'email'=>'a
        bcdef@abcdef', 'id'=>'ABC'}, '
        version'=>4, 'status'=>'succee
        ded'}]
        => [{"user"=>{"email"=>"abcdef
        @abcdef", "id"=>"ABC"}, "versi
        on"=>4, "status"=>"succeeded"}
        ]
        prompt>
      EOC
    end

    def test_finish_autowrapped_line_in_the_middle_of_multilines
      start_terminal(30, 16, %W{ruby -I#{@pwd}/lib #{@pwd}/bin/multiline_repl}, startup_message: 'Multiline REPL.')
      write("<<~EOM\n  ABCDEFG\nEOM\n")
      close
      assert_screen(<<~'EOC')
        Multiline REPL.
        prompt> <<~EOM
        prompt>   ABCDEF
        G
        prompt> EOM
        => "ABCDEFG\n"
        prompt>
      EOC
    end

    def test_prompt
      write_inputrc <<~'LINES'
        "abc": "123"
      LINES
      start_terminal(5, 30, %W{ruby -I#{@pwd}/lib #{@pwd}/bin/multiline_repl}, startup_message: 'Multiline REPL.')
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
      write_inputrc <<~LINES
        set show-mode-in-prompt on
      LINES
      start_terminal(5, 30, %W{ruby -I#{@pwd}/lib #{@pwd}/bin/multiline_repl}, startup_message: 'Multiline REPL.')
      close
      assert_screen(<<~EOC)
        Multiline REPL.
        @prompt>
      EOC
    end

    def test_mode_icon_vi
      write_inputrc <<~LINES
        set editing-mode vi
        set show-mode-in-prompt on
      LINES
      start_terminal(5, 30, %W{ruby -I#{@pwd}/lib #{@pwd}/bin/multiline_repl}, startup_message: 'Multiline REPL.')
      write(":a\n\C-[k")
      close
      assert_screen(<<~EOC)
        Multiline REPL.
        (ins)prompt> :a
        => :a
        (cmd)prompt> :a
      EOC
    end

    def test_original_mode_icon_emacs
      write_inputrc <<~LINES
        set show-mode-in-prompt on
        set emacs-mode-string [emacs]
      LINES
      start_terminal(5, 30, %W{ruby -I#{@pwd}/lib #{@pwd}/bin/multiline_repl}, startup_message: 'Multiline REPL.')
      close
      assert_screen(<<~EOC)
        Multiline REPL.
        [emacs]prompt>
      EOC
    end

    def test_original_mode_icon_with_quote
      write_inputrc <<~LINES
        set show-mode-in-prompt on
        set emacs-mode-string "[emacs]"
      LINES
      start_terminal(5, 30, %W{ruby -I#{@pwd}/lib #{@pwd}/bin/multiline_repl}, startup_message: 'Multiline REPL.')
      close
      assert_screen(<<~EOC)
        Multiline REPL.
        [emacs]prompt>
      EOC
    end

    def test_original_mode_icon_vi
      write_inputrc <<~LINES
        set editing-mode vi
        set show-mode-in-prompt on
        set vi-ins-mode-string "{InS}"
        set vi-cmd-mode-string "{CmD}"
      LINES
      start_terminal(5, 30, %W{ruby -I#{@pwd}/lib #{@pwd}/bin/multiline_repl}, startup_message: 'Multiline REPL.')
      write(":a\n\C-[k")
      close
      assert_screen(<<~EOC)
        Multiline REPL.
        {InS}prompt> :a
        => :a
        {CmD}prompt> :a
      EOC
    end

    def test_mode_icon_vi_changing
      write_inputrc <<~LINES
        set editing-mode vi
        set show-mode-in-prompt on
      LINES
      start_terminal(5, 30, %W{ruby -I#{@pwd}/lib #{@pwd}/bin/multiline_repl}, startup_message: 'Multiline REPL.')
      write(":a\C-[ab\C-[ac\C-h\C-h\C-h\C-h:a")
      close
      assert_screen(<<~EOC)
        Multiline REPL.
        (ins)prompt> :a
      EOC
    end

    def test_prompt_with_escape_sequence
      ENV['RELINE_TEST_PROMPT'] = "\1\e[30m\2prompt> \1\e[m\2"
      start_terminal(5, 20, %W{ruby -I#{@pwd}/lib #{@pwd}/bin/multiline_repl}, startup_message: 'Multiline REPL.')
      write("123\n")
      close
      assert_screen(<<~EOC)
        Multiline REPL.
        prompt> 123
        => 123
        prompt>
      EOC
    end

    def test_prompt_with_escape_sequence_and_autowrap
      ENV['RELINE_TEST_PROMPT'] = "\1\e[30m\2prompt> \1\e[m\2"
      start_terminal(5, 20, %W{ruby -I#{@pwd}/lib #{@pwd}/bin/multiline_repl}, startup_message: 'Multiline REPL.')
      write("1234567890123\n")
      close
      assert_screen(<<~EOC)
        Multiline REPL.
        prompt> 123456789012
        3
        => 1234567890123
        prompt>
      EOC
    end

    def test_multiline_and_autowrap
      start_terminal(10, 20, %W{ruby -I#{@pwd}/lib #{@pwd}/bin/multiline_repl}, startup_message: 'Multiline REPL.')
      write("def aaaaaaaaaa\n  33333333\n           end\C-a\C-pputs\C-e\e\C-m888888888888888")
      close
      assert_screen(<<~EOC)
        Multiline REPL.
        prompt> def aaaaaaaa
        aa
        prompt> puts  333333
        33
        prompt> 888888888888
        888
        prompt>            e
        nd
      EOC
    end

    def test_clear
      start_terminal(10, 15, %W{ruby -I#{@pwd}/lib #{@pwd}/bin/multiline_repl}, startup_message: 'Multiline REPL.')
      write("3\C-l")
      close
      assert_screen(<<~EOC)
        prompt> 3
      EOC
    end

    def test_clear_multiline_and_autowrap
      omit # FIXME clear logic is buggy
      start_terminal(10, 15, %W{ruby -I#{@pwd}/lib #{@pwd}/bin/multiline_repl}, startup_message: 'Multiline REPL.')
      write("def aaaaaa\n  3\n\C-lend")
      close
      assert_screen(<<~EOC)
        prompt> def aaa
        aaa
        prompt>   3
        prompt> end
      EOC
    end

    def test_nearest_cursor
      start_terminal(10, 20, %W{ruby -I#{@pwd}/lib #{@pwd}/bin/multiline_repl}, startup_message: 'Multiline REPL.')
      write("def ああ\n  :いい\nend\C-pbb\C-pcc")
      close
      assert_screen(<<~EOC)
        Multiline REPL.
        prompt> def ccああ
        prompt>   :bbいい
        prompt> end
      EOC
    end

    def test_delete_line
      start_terminal(10, 20, %W{ruby -I#{@pwd}/lib #{@pwd}/bin/multiline_repl}, startup_message: 'Multiline REPL.')
      write("def a\n\nend\C-p\C-h")
      close
      assert_screen(<<~EOC)
        Multiline REPL.
        prompt> def a
        prompt> end
      EOC
    end

    def test_last_line_of_screen
      start_terminal(5, 20, %W{ruby -I#{@pwd}/lib #{@pwd}/bin/multiline_repl}, startup_message: 'Multiline REPL.')
      write("\n\n\n\n\ndef a\nend")
      close
      assert_screen(<<~EOC)
        prompt>
        prompt>
        prompt>
        prompt> def a
        prompt> end
      EOC
    end

    # c17a09b7454352e2aff5a7d8722e80afb73e454b
    def test_autowrap_at_last_line_of_screen
      start_terminal(5, 15, %W{ruby -I#{@pwd}/lib #{@pwd}/bin/multiline_repl}, startup_message: 'Multiline REPL.')
      write("def a\nend\n\C-p")
      close
      assert_screen(<<~EOC)
        prompt> def a
        prompt> end
        => :a
        prompt> def a
        prompt> end
      EOC
    end

    # f002483b27cdb325c5edf9e0fe4fa4e1c71c4b0e
    def test_insert_line_in_the_middle_of_line
      start_terminal(5, 20, %W{ruby -I#{@pwd}/lib #{@pwd}/bin/multiline_repl}, startup_message: 'Multiline REPL.')
      write("333\C-b\C-b\e\C-m8")
      close
      assert_screen(<<~EOC)
        Multiline REPL.
        prompt> 3
        prompt> 833
      EOC
    end

    # 9d8978961c5de5064f949d56d7e0286df9e18f43
    def test_insert_line_in_the_middle_of_line_at_last_line_of_screen
      start_terminal(3, 20, %W{ruby -I#{@pwd}/lib #{@pwd}/bin/multiline_repl}, startup_message: 'Multiline REPL.')
      write("333333333333333\C-a\C-f\e\C-m")
      close
      assert_screen(<<~EOC)
        prompt> 3
        prompt> 333333333333
        33
      EOC
    end

    def test_insert_after_clear
      start_terminal(10, 20, %W{ruby -I#{@pwd}/lib #{@pwd}/bin/multiline_repl}, startup_message: 'Multiline REPL.')
      write("def a\n  01234\nend\C-l\C-p5678")
      close
      assert_screen(<<~EOC)
        prompt> def a
        prompt>   056781234
        prompt> end
      EOC
    end

    def test_foced_newline_insertion
      start_terminal(10, 20, %W{ruby -I#{@pwd}/lib #{@pwd}/bin/multiline_repl}, startup_message: 'Multiline REPL.')
      #write("def a\nend\C-p\C-e\e\C-m  3")
      write("def a\nend\C-p\C-e\e\x0D")
      close
      assert_screen(<<~EOC)
        Multiline REPL.
        prompt> def a
        prompt>
        prompt> end
      EOC
    end

    def test_multiline_incremental_search
      start_terminal(6, 25, %W{ruby -I#{@pwd}/lib #{@pwd}/bin/multiline_repl}, startup_message: 'Multiline REPL.')
      write("def a\n  8\nend\ndef b\n  3\nend\C-s8")
      close
      assert_screen(<<~EOC)
        (i-search)`8'def a
        (i-search)`8'  8
        (i-search)`8'end
      EOC
    end

    def test_multiline_incremental_search_finish
      start_terminal(6, 25, %W{ruby -I#{@pwd}/lib #{@pwd}/bin/multiline_repl}, startup_message: 'Multiline REPL.')
      write("def a\n  8\nend\ndef b\n  3\nend\C-r8\C-j")
      close
      assert_screen(<<~EOC)
        prompt> def a
        prompt>   8
        prompt> end
      EOC
    end

    def test_binding_for_vi_movement_mode
      write_inputrc <<~LINES
        set editing-mode vi
        "\\C-j": vi-movement-mode
      LINES
      start_terminal(5, 30, %W{ruby -I#{@pwd}/lib #{@pwd}/bin/multiline_repl}, startup_message: 'Multiline REPL.')
      write(":1234\C-jhhhi0")
      close
      assert_screen(<<~EOC)
        Multiline REPL.
        prompt> :01234
      EOC
    end

    def test_prompt_list_caching
      start_terminal(5, 30, %W{ruby -I#{@pwd}/lib #{@pwd}/bin/multiline_repl --prompt-list-cache-timeout 10 --dynamic-prompt}, startup_message: 'Multiline REPL.')
      write("def hoge\n  3\nend")
      close
      assert_screen(<<~EOC)
        Multiline REPL.
        [0000]> def hoge
        [0001]>   3
        [0002]> end
      EOC
    end

    def test_enable_bracketed_paste
      omit if Reline::IOGate.win?
      write_inputrc <<~LINES
        set enable-bracketed-paste on
      LINES
      start_terminal(5, 30, %W{ruby -I#{@pwd}/lib #{@pwd}/bin/multiline_repl}, startup_message: 'Multiline REPL.')
      write("\e[200~,")
      write("def hoge\n  3\nend")
      write("\e[200~.")
      close
      assert_screen(<<~EOC)
        Multiline REPL.
        prompt> def hoge
        prompt>   3
        prompt> end
      EOC
    end

    def test_backspace_until_returns_to_initial
      start_terminal(5, 30, %W{ruby -I#{@pwd}/lib #{@pwd}/bin/multiline_repl}, startup_message: 'Multiline REPL.')
      write("ABC")
      write("\C-h\C-h\C-h")
      close
      assert_screen(<<~EOC)
        Multiline REPL.
        prompt>
      EOC
    end

    def test_longer_than_screen_height
      start_terminal(5, 30, %W{ruby -I#{@pwd}/lib #{@pwd}/bin/multiline_repl}, startup_message: 'Multiline REPL.')
      write(<<~EOC.chomp)
        def each_top_level_statement
          initialize_input
          catch(:TERM_INPUT) do
            loop do
              begin
                prompt
                unless l = lex
                  throw :TERM_INPUT if @line == ''
                else
                  @line_no += l.count("\n")
                  next if l == "\n"
                  @line.concat l
                  if @code_block_open or @ltype or @continue or @indent > 0
                    next
                  end
                end
                if @line != "\n"
                  @line.force_encoding(@io.encoding)
                  yield @line, @exp_line_no
                end
                break if @io.eof?
                @line = ''
                @exp_line_no = @line_no
                #
                @indent = 0
              rescue TerminateLineInput
                initialize_input
                prompt
              end
            end
          end
        end
      EOC
      close
      assert_screen(<<~EOC)
        prompt>         prompt
        prompt>       end
        prompt>     end
        prompt>   end
        prompt> end
      EOC
    end

    def test_longer_than_screen_height_with_scroll_back
      start_terminal(5, 30, %W{ruby -I#{@pwd}/lib #{@pwd}/bin/multiline_repl}, startup_message: 'Multiline REPL.')
      write(<<~EOC.chomp)
        def each_top_level_statement
          initialize_input
          catch(:TERM_INPUT) do
            loop do
              begin
                prompt
                unless l = lex
                  throw :TERM_INPUT if @line == ''
                else
                  @line_no += l.count("\n")
                  next if l == "\n"
                  @line.concat l
                  if @code_block_open or @ltype or @continue or @indent > 0
                    next
                  end
                end
                if @line != "\n"
                  @line.force_encoding(@io.encoding)
                  yield @line, @exp_line_no
                end
                break if @io.eof?
                @line = ''
                @exp_line_no = @line_no
                #
                @indent = 0
              rescue TerminateLineInput
                initialize_input
                prompt
              end
            end
          end
        end
      EOC
      write("\C-p" * 6)
      close
      assert_screen(<<~EOC)
        prompt>       rescue Terminate
        LineInput
        prompt>         initialize_inp
        ut
        prompt>         prompt
      EOC
    end

    def test_longer_than_screen_height_with_complex_scroll_back
      start_terminal(4, 30, %W{ruby -I#{@pwd}/lib #{@pwd}/bin/multiline_repl}, startup_message: 'Multiline REPL.')
      write(<<~EOC.chomp)
        def each_top_level_statement
          initialize_input
          catch(:TERM_INPUT) do
            loop do
              begin
                prompt
                unless l = lex
                  throw :TERM_INPUT if @line == ''
                else
                  @line_no += l.count("\n")
                  next if l == "\n"
                  @line.concat l
                  if @code_block_open or @ltype or @continue or @indent > 0
                    next
                  end
                end
                if @line != "\n"
                  @line.force_encoding(@io.encoding)
                  yield @line, @exp_line_no
                end
                break if @io.eof?
                @line = ''
                @exp_line_no = @line_no
                #
                @indent = 0
              rescue TerminateLineInput
                initialize_input
                prompt
              end
            end
          end
        end
      EOC
      sleep 0.3
      write("\C-p" * 5)
      write("\C-n" * 3)
      close
      assert_screen(<<~EOC)
        ut
        prompt>         prompt
        prompt>       end
        prompt>     end
      EOC
    end

    private def write_inputrc(content)
      File.open(@inputrc_file, 'w') do |f|
        f.write content
      end
    end
  end
rescue LoadError, NameError
  # On Ruby repository, this test suit doesn't run because Ruby repo doesn't
  # have the yamatanooroti gem.
end
