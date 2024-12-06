require 'reline'

begin
  require 'yamatanooroti'

  class Reline::RenderingTest < Yamatanooroti::TestCase

    FACE_CONFIGS = { no_config: "", valid_config: <<~VALID_CONFIG, incomplete_config: <<~INCOMPLETE_CONFIG }
      require "reline"
      Reline::Face.config(:completion_dialog) do |face|
        face.define :default, foreground: :white, background: :blue
        face.define :enhanced, foreground: :white, background: :magenta
        face.define :scrollbar, foreground: :white, background: :blue
      end
    VALID_CONFIG
      require "reline"
      Reline::Face.config(:completion_dialog) do |face|
        face.define :default, foreground: :white, background: :black
        face.define :scrollbar, foreground: :white, background: :cyan
      end
    INCOMPLETE_CONFIG

    def iterate_over_face_configs(&block)
      FACE_CONFIGS.each do |config_name, face_config|
        config_file = Tempfile.create(%w{face_config- .rb})
        config_file.write face_config
        block.call(config_name, config_file)
      ensure
        config_file.close
        File.delete(config_file)
      end
    end

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
      @inputrc_backup = ENV['INPUTRC']
      @inputrc_file = ENV['INPUTRC'] = File.join(@tmpdir, 'temporaty_inputrc')
      File.unlink(@inputrc_file) if File.exist?(@inputrc_file)
    end

    def teardown
      FileUtils.rm_rf(@tmpdir)
      ENV['INPUTRC'] = @inputrc_backup
      ENV.delete('RELINE_TEST_PROMPT') if ENV['RELINE_TEST_PROMPT']
    end

    def test_history_back
      start_terminal(5, 30, %W{ruby -I#{@pwd}/lib #{@pwd}/test/reline/yamatanooroti/multiline_repl}, startup_message: 'Multiline REPL.')
      write(":a\n")
      write("\C-p")
      assert_screen(<<~EOC)
        Multiline REPL.
        prompt> :a
        => :a
        prompt> :a
      EOC
      close
    end

    def test_backspace
      start_terminal(5, 30, %W{ruby -I#{@pwd}/lib #{@pwd}/test/reline/yamatanooroti/multiline_repl}, startup_message: 'Multiline REPL.')
      write(":abc\C-h\n")
      assert_screen(<<~EOC)
        Multiline REPL.
        prompt> :ab
        => :ab
        prompt>
      EOC
      close
    end

    def test_autowrap
      start_terminal(5, 30, %W{ruby -I#{@pwd}/lib #{@pwd}/test/reline/yamatanooroti/multiline_repl}, startup_message: 'Multiline REPL.')
      write('01234567890123456789012')
      assert_screen(<<~EOC)
        Multiline REPL.
        prompt> 0123456789012345678901
        2
      EOC
      close
    end

    def test_fullwidth
      start_terminal(5, 30, %W{ruby -I#{@pwd}/lib #{@pwd}/test/reline/yamatanooroti/multiline_repl}, startup_message: 'Multiline REPL.')
      write(":あ\n")
      assert_screen(<<~EOC)
        Multiline REPL.
        prompt> :あ
        => :あ
        prompt>
      EOC
      close
    end

    def test_two_fullwidth
      start_terminal(5, 30, %W{ruby -I#{@pwd}/lib #{@pwd}/test/reline/yamatanooroti/multiline_repl}, startup_message: 'Multiline REPL.')
      write(":あい\n")
      assert_screen(<<~EOC)
        Multiline REPL.
        prompt> :あい
        => :あい
        prompt>
      EOC
      close
    end

    def test_finish_autowrapped_line
      start_terminal(10, 40, %W{ruby -I#{@pwd}/lib #{@pwd}/test/reline/yamatanooroti/multiline_repl}, startup_message: 'Multiline REPL.')
      write("[{'user'=>{'email'=>'a@a', 'id'=>'ABC'}, 'version'=>4, 'status'=>'succeeded'}]\n")
      expected = [{'user'=>{'email'=>'a@a', 'id'=>'ABC'}, 'version'=>4, 'status'=>'succeeded'}].inspect
      assert_screen(<<~EOC)
        Multiline REPL.
        prompt> [{'user'=>{'email'=>'a@a', 'id'=
        >'ABC'}, 'version'=>4, 'status'=>'succee
        ded'}]
        #{fold_multiline("=> " + expected, 40)}
        prompt>
      EOC
      close
    end

    def test_finish_autowrapped_line_in_the_middle_of_lines
      start_terminal(20, 30, %W{ruby -I#{@pwd}/lib #{@pwd}/test/reline/yamatanooroti/multiline_repl}, startup_message: 'Multiline REPL.')
      write("[{'user'=>{'email'=>'abcdef@abcdef', 'id'=>'ABC'}, 'version'=>4, 'status'=>'succeeded'}]#{"\C-b"*7}")
      write("\n")
      expected = [{'user'=>{'email'=>'abcdef@abcdef', 'id'=>'ABC'}, 'version'=>4, 'status'=>'succeeded'}].inspect
      assert_screen(<<~EOC)
        Multiline REPL.
        prompt> [{'user'=>{'email'=>'a
        bcdef@abcdef', 'id'=>'ABC'}, '
        version'=>4, 'status'=>'succee
        ded'}]
        #{fold_multiline("=> " + expected, 30)}
        prompt>
      EOC
      close
    end

    def test_finish_autowrapped_line_in_the_middle_of_multilines
      omit if RUBY_VERSION < '2.7'
      start_terminal(30, 16, %W{ruby -I#{@pwd}/lib #{@pwd}/test/reline/yamatanooroti/multiline_repl}, startup_message: 'Multiline REPL.')
      write("<<~EOM\n  ABCDEFG\nEOM\n")
      assert_screen(<<~'EOC')
        Multiline REPL.
        prompt> <<~EOM
        prompt>   ABCDEF
        G
        prompt> EOM
        => "ABCDEFG\n"
        prompt>
      EOC
      close
    end

    def test_prompt
      write_inputrc <<~'LINES'
        "abc": "123"
      LINES
      start_terminal(5, 30, %W{ruby -I#{@pwd}/lib #{@pwd}/test/reline/yamatanooroti/multiline_repl}, startup_message: 'Multiline REPL.')
      write("abc\n")
      assert_screen(<<~EOC)
        Multiline REPL.
        prompt> 123
        => 123
        prompt>
      EOC
      close
    end

    def test_mode_string_emacs
      write_inputrc <<~LINES
        set show-mode-in-prompt on
      LINES
      start_terminal(5, 30, %W{ruby -I#{@pwd}/lib #{@pwd}/test/reline/yamatanooroti/multiline_repl}, startup_message: 'Multiline REPL.')
      assert_screen(<<~EOC)
        Multiline REPL.
        @prompt>
      EOC
      close
    end

    def test_mode_string_vi
      write_inputrc <<~LINES
        set editing-mode vi
        set show-mode-in-prompt on
      LINES
      start_terminal(5, 30, %W{ruby -I#{@pwd}/lib #{@pwd}/test/reline/yamatanooroti/multiline_repl}, startup_message: 'Multiline REPL.')
      write(":a\n\C-[k")
      write("i\n:a")
      write("\C-[h")
      assert_screen(<<~EOC)
        (ins)prompt> :a
        => :a
        (ins)prompt> :a
        => :a
        (cmd)prompt> :a
      EOC
      close
    end

    def test_original_mode_string_emacs
      write_inputrc <<~LINES
        set show-mode-in-prompt on
        set emacs-mode-string [emacs]
      LINES
      start_terminal(5, 30, %W{ruby -I#{@pwd}/lib #{@pwd}/test/reline/yamatanooroti/multiline_repl}, startup_message: 'Multiline REPL.')
      assert_screen(<<~EOC)
        Multiline REPL.
        [emacs]prompt>
      EOC
      close
    end

    def test_original_mode_string_with_quote
      write_inputrc <<~LINES
        set show-mode-in-prompt on
        set emacs-mode-string "[emacs]"
      LINES
      start_terminal(5, 30, %W{ruby -I#{@pwd}/lib #{@pwd}/test/reline/yamatanooroti/multiline_repl}, startup_message: 'Multiline REPL.')
      assert_screen(<<~EOC)
        Multiline REPL.
        [emacs]prompt>
      EOC
      close
    end

    def test_original_mode_string_vi
      write_inputrc <<~LINES
        set editing-mode vi
        set show-mode-in-prompt on
        set vi-ins-mode-string "{InS}"
        set vi-cmd-mode-string "{CmD}"
      LINES
      start_terminal(5, 30, %W{ruby -I#{@pwd}/lib #{@pwd}/test/reline/yamatanooroti/multiline_repl}, startup_message: 'Multiline REPL.')
      write(":a\n\C-[k")
      assert_screen(<<~EOC)
        Multiline REPL.
        {InS}prompt> :a
        => :a
        {CmD}prompt> :a
      EOC
      close
    end

    def test_mode_string_vi_changing
      write_inputrc <<~LINES
        set editing-mode vi
        set show-mode-in-prompt on
      LINES
      start_terminal(5, 30, %W{ruby -I#{@pwd}/lib #{@pwd}/test/reline/yamatanooroti/multiline_repl}, startup_message: 'Multiline REPL.')
      write(":a\C-[ab\C-[ac\C-h\C-h\C-h\C-h:a")
      assert_screen(<<~EOC)
        Multiline REPL.
        (ins)prompt> :a
      EOC
      close
    end

    def test_esc_input
      omit if Reline::IOGate.win?
      start_terminal(5, 20, %W{ruby -I#{@pwd}/lib #{@pwd}/test/reline/yamatanooroti/multiline_repl}, startup_message: 'Multiline REPL.')
      write("def\C-aabc")
      write("\e") # single ESC
      sleep 1
      write("A")
      write("B\eAC") # ESC + A (M-A, no key specified in Reline::KeyActor::Emacs)
      assert_screen(<<~EOC)
        Multiline REPL.
        prompt> abcABCdef
      EOC
      close
    end

    def test_prompt_with_escape_sequence
      ENV['RELINE_TEST_PROMPT'] = "\1\e[30m\2prompt> \1\e[m\2"
      start_terminal(5, 20, %W{ruby -I#{@pwd}/lib #{@pwd}/test/reline/yamatanooroti/multiline_repl}, startup_message: 'Multiline REPL.')
      write("123\n")
      assert_screen(<<~EOC)
        Multiline REPL.
        prompt> 123
        => 123
        prompt>
      EOC
      close
    end

    def test_prompt_with_escape_sequence_and_autowrap
      ENV['RELINE_TEST_PROMPT'] = "\1\e[30m\2prompt> \1\e[m\2"
      start_terminal(5, 20, %W{ruby -I#{@pwd}/lib #{@pwd}/test/reline/yamatanooroti/multiline_repl}, startup_message: 'Multiline REPL.')
      write("1234567890123\n")
      assert_screen(<<~EOC)
        Multiline REPL.
        prompt> 123456789012
        3
        => 1234567890123
        prompt>
      EOC
      close
    end

    def test_readline_with_multiline_input
      start_terminal(5, 50, %W{ruby -I#{@pwd}/lib #{@pwd}/test/reline/yamatanooroti/multiline_repl --dynamic-prompt}, startup_message: 'Multiline REPL.')
      write("def foo\n  bar\nend\n")
      write("Reline.readline('prompt> ')\n")
      write("\C-p\C-p")
      assert_screen(<<~EOC)
        => :foo
        [0000]> Reline.readline('prompt> ')
        prompt> def foo
          bar
        end
      EOC
      close
    end

    def test_multiline_and_autowrap
      start_terminal(10, 20, %W{ruby -I#{@pwd}/lib #{@pwd}/test/reline/yamatanooroti/multiline_repl}, startup_message: 'Multiline REPL.')
      write("def aaaaaaaaaa\n  33333333\n           end\C-a\C-pputs\C-e\e\C-m888888888888888")
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
      close
    end

    def test_multiline_add_new_line_and_autowrap
      start_terminal(10, 20, %W{ruby -I#{@pwd}/lib #{@pwd}/test/reline/yamatanooroti/multiline_repl}, startup_message: 'Multiline REPL.')
      write("def aaaaaaaaaa")
      write("\n")
      write("  bbbbbbbbbbbb")
      write("\n")
      assert_screen(<<~EOC)
        Multiline REPL.
        prompt> def aaaaaaaa
        aa
        prompt>   bbbbbbbbbb
        bb
        prompt>
      EOC
      close
    end

    def test_clear
      start_terminal(10, 15, %W{ruby -I#{@pwd}/lib #{@pwd}/test/reline/yamatanooroti/multiline_repl}, startup_message: 'Multiline REPL.')
      write("3\C-l")
      assert_screen(<<~EOC)
        prompt> 3
      EOC
      close
    end

    def test_clear_multiline_and_autowrap
      start_terminal(10, 15, %W{ruby -I#{@pwd}/lib #{@pwd}/test/reline/yamatanooroti/multiline_repl}, startup_message: 'Multiline REPL.')
      write("def aaaaaa\n  3\n\C-lend")
      assert_screen(<<~EOC)
        prompt> def aaa
        aaa
        prompt>   3
        prompt> end
      EOC
      close
    end

    def test_nearest_cursor
      start_terminal(10, 20, %W{ruby -I#{@pwd}/lib #{@pwd}/test/reline/yamatanooroti/multiline_repl}, startup_message: 'Multiline REPL.')
      write("def ああ\n  :いい\nend\C-pbb\C-pcc")
      assert_screen(<<~EOC)
        Multiline REPL.
        prompt> def ccああ
        prompt>   :bbいい
        prompt> end
      EOC
      close
    end

    def test_delete_line
      start_terminal(10, 20, %W{ruby -I#{@pwd}/lib #{@pwd}/test/reline/yamatanooroti/multiline_repl}, startup_message: 'Multiline REPL.')
      write("def a\n\nend\C-p\C-h")
      assert_screen(<<~EOC)
        Multiline REPL.
        prompt> def a
        prompt> end
      EOC
      close
    end

    def test_last_line_of_screen
      start_terminal(5, 20, %W{ruby -I#{@pwd}/lib #{@pwd}/test/reline/yamatanooroti/multiline_repl}, startup_message: 'Multiline REPL.')
      write("\n\n\n\n\ndef a\nend")
      assert_screen(<<~EOC)
        prompt>
        prompt>
        prompt>
        prompt> def a
        prompt> end
      EOC
      close
    end

    # c17a09b7454352e2aff5a7d8722e80afb73e454b
    def test_autowrap_at_last_line_of_screen
      start_terminal(5, 15, %W{ruby -I#{@pwd}/lib #{@pwd}/test/reline/yamatanooroti/multiline_repl}, startup_message: 'Multiline REPL.')
      write("def a\nend\n\C-p")
      assert_screen(<<~EOC)
        prompt> def a
        prompt> end
        => :a
        prompt> def a
        prompt> end
      EOC
      close
    end

    # f002483b27cdb325c5edf9e0fe4fa4e1c71c4b0e
    def test_insert_line_in_the_middle_of_line
      start_terminal(5, 20, %W{ruby -I#{@pwd}/lib #{@pwd}/test/reline/yamatanooroti/multiline_repl}, startup_message: 'Multiline REPL.')
      write("333\C-b\C-b\e\C-m8")
      assert_screen(<<~EOC)
        Multiline REPL.
        prompt> 3
        prompt> 833
      EOC
      close
    end

    # 9d8978961c5de5064f949d56d7e0286df9e18f43
    def test_insert_line_in_the_middle_of_line_at_last_line_of_screen
      start_terminal(3, 20, %W{ruby -I#{@pwd}/lib #{@pwd}/test/reline/yamatanooroti/multiline_repl}, startup_message: 'Multiline REPL.')
      write("333333333333333\C-a\C-f\e\C-m")
      assert_screen(<<~EOC)
        prompt> 3
        prompt> 333333333333
        33
      EOC
      close
    end

    def test_insert_after_clear
      start_terminal(10, 20, %W{ruby -I#{@pwd}/lib #{@pwd}/test/reline/yamatanooroti/multiline_repl}, startup_message: 'Multiline REPL.')
      write("def a\n  01234\nend\C-l\C-p5678")
      assert_screen(<<~EOC)
        prompt> def a
        prompt>   056781234
        prompt> end
      EOC
      close
    end

    def test_foced_newline_insertion
      start_terminal(10, 20, %W{ruby -I#{@pwd}/lib #{@pwd}/test/reline/yamatanooroti/multiline_repl}, startup_message: 'Multiline REPL.')
      #write("def a\nend\C-p\C-e\e\C-m  3")
      write("def a\nend\C-p\C-e\e\x0D")
      assert_screen(<<~EOC)
        Multiline REPL.
        prompt> def a
        prompt>
        prompt> end
      EOC
      close
    end

    def test_multiline_incremental_search
      start_terminal(6, 25, %W{ruby -I#{@pwd}/lib #{@pwd}/test/reline/yamatanooroti/multiline_repl}, startup_message: 'Multiline REPL.')
      write("def a\n  8\nend\ndef b\n  3\nend\C-s8")
      assert_screen(<<~EOC)
        prompt>   8
        prompt> end
        => :a
        (i-search)`8'def a
        (i-search)`8'  8
        (i-search)`8'end
      EOC
      close
    end

    def test_multiline_incremental_search_finish
      start_terminal(6, 25, %W{ruby -I#{@pwd}/lib #{@pwd}/test/reline/yamatanooroti/multiline_repl}, startup_message: 'Multiline REPL.')
      write("def a\n  8\nend\ndef b\n  3\nend\C-r8\C-j")
      assert_screen(<<~EOC)
        prompt>   8
        prompt> end
        => :a
        prompt> def a
        prompt>   8
        prompt> end
      EOC
      close
    end

    def test_binding_for_vi_movement_mode
      write_inputrc <<~LINES
        set editing-mode vi
        "\\C-a": vi-movement-mode
      LINES
      start_terminal(5, 30, %W{ruby -I#{@pwd}/lib #{@pwd}/test/reline/yamatanooroti/multiline_repl}, startup_message: 'Multiline REPL.')
      write(":1234\C-ahhhi0")
      assert_screen(<<~EOC)
        Multiline REPL.
        prompt> :01234
      EOC
      close
    end

    def test_broken_prompt_list
      start_terminal(5, 30, %W{ruby -I#{@pwd}/lib #{@pwd}/test/reline/yamatanooroti/multiline_repl --broken-dynamic-prompt}, startup_message: 'Multiline REPL.')
      write("def hoge\n  3\nend")
      assert_screen(<<~EOC)
        Multiline REPL.
        [0000]> def hoge
        [0001]>   3
        [0001]> end
      EOC
      close
    end

    def test_no_escape_sequence_passed_to_dynamic_prompt
      start_terminal(10, 30, %W{ruby -I#{@pwd}/lib #{@pwd}/test/reline/yamatanooroti/multiline_repl  --autocomplete --color-bold --broken-dynamic-prompt-assert-no-escape-sequence}, startup_message: 'Multiline REPL.')
      write("%[ S")
      write("\n")
      assert_screen(<<~EOC)
        Multiline REPL.
        [0000]> %[ S
        [0001]>
      EOC
      close
    end

    def test_bracketed_paste
      omit if Reline.core.io_gate.win?
      start_terminal(5, 30, %W{ruby -I#{@pwd}/lib #{@pwd}/test/reline/yamatanooroti/multiline_repl}, startup_message: 'Multiline REPL.')
      write("\e[200~def hoge\r\t3\rend\e[201~")
      assert_screen(<<~EOC)
        Multiline REPL.
        prompt> def hoge
        prompt>   3
        prompt> end
      EOC
      close
    end

    def test_bracketed_paste_with_undo_redo
      omit if Reline.core.io_gate.win?
      start_terminal(5, 30, %W{ruby -I#{@pwd}/lib #{@pwd}/test/reline/yamatanooroti/multiline_repl}, startup_message: 'Multiline REPL.')
      write("abc")
      write("\e[200~def hoge\r\t3\rend\e[201~")
      write("\C-_")
      assert_screen(<<~EOC)
        Multiline REPL.
        prompt> abc
      EOC
      write("\M-\C-_")
      assert_screen(<<~EOC)
        Multiline REPL.
        prompt> abcdef hoge
        prompt>   3
        prompt> end
      EOC
      close
    end

    def test_backspace_until_returns_to_initial
      start_terminal(5, 30, %W{ruby -I#{@pwd}/lib #{@pwd}/test/reline/yamatanooroti/multiline_repl}, startup_message: 'Multiline REPL.')
      write("ABC")
      write("\C-h\C-h\C-h")
      assert_screen(<<~EOC)
        Multiline REPL.
        prompt>
      EOC
      close
    end

    def test_longer_than_screen_height
      start_terminal(5, 30, %W{ruby -I#{@pwd}/lib #{@pwd}/test/reline/yamatanooroti/multiline_repl}, startup_message: 'Multiline REPL.')
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
      assert_screen(<<~EOC)
        prompt>         prompt
        prompt>       end
        prompt>     end
        prompt>   end
        prompt> end
      EOC
      write("\C-p" * 6)
      assert_screen(<<~EOC)
        prompt>       rescue Terminate
        LineInput
        prompt>         initialize_inp
        ut
        prompt>         prompt
      EOC
      write("\C-n" * 4)
      assert_screen(<<~EOC)
        prompt>         initialize_inp
        ut
        prompt>         prompt
        prompt>       end
        prompt>     end
      EOC
      close
    end

    def test_longer_than_screen_height_nearest_cursor_with_scroll_back
      start_terminal(5, 30, %W{ruby -I#{@pwd}/lib #{@pwd}/test/reline/yamatanooroti/multiline_repl}, startup_message: 'Multiline REPL.')
      write(<<~EOC.chomp)
        if 1
          if 2
            if 3
              if 4
                puts
              end
            end
          end
        end
      EOC
      write("\C-p" * 4 + "\C-e" + "\C-p" * 4)
      write("2")
      assert_screen(<<~EOC)
        prompt> if 12
        prompt>   if 2
        prompt>     if 3
        prompt>       if 4
        prompt>         puts
      EOC
      close
    end

    def test_update_cursor_correctly_when_just_cursor_moving
      start_terminal(5, 30, %W{ruby -I#{@pwd}/lib #{@pwd}/test/reline/yamatanooroti/multiline_repl}, startup_message: 'Multiline REPL.')
      write("def hoge\n  01234678")
      write("\C-p")
      write("\C-b")
      write("\C-n")
      write('5')
      write("\C-e")
      write('9')
      assert_screen(<<~EOC)
        Multiline REPL.
        prompt> def hoge
        prompt>   0123456789
      EOC
      close
    end

    def test_auto_indent
      start_terminal(10, 30, %W{ruby -I#{@pwd}/lib #{@pwd}/test/reline/yamatanooroti/multiline_repl --auto-indent}, startup_message: 'Multiline REPL.')
      "def hoge\nputs(\n1,\n2\n)\nend".lines do |line|
        write line
      end
      assert_screen(<<~EOC)
        Multiline REPL.
        prompt> def hoge
        prompt>   puts(
        prompt>     1,
        prompt>     2
        prompt>   )
        prompt> end
      EOC
      close
    end

    def test_auto_indent_when_inserting_line
      start_terminal(5, 30, %W{ruby -I#{@pwd}/lib #{@pwd}/test/reline/yamatanooroti/multiline_repl --auto-indent}, startup_message: 'Multiline REPL.')
      write 'aa(bb(cc(dd(ee('
      write "\C-b" * 5 + "\n"
      assert_screen(<<~EOC)
        Multiline REPL.
        prompt> aa(bb(cc(d
        prompt>       d(ee(
      EOC
      close
    end

    def test_auto_indent_multibyte_insert_line
      start_terminal(10, 30, %W{ruby -I#{@pwd}/lib #{@pwd}/test/reline/yamatanooroti/multiline_repl --auto-indent}, startup_message: 'Multiline REPL.')
      write "if true\n"
      write "あいうえお\n"
      4.times { write "\C-b\C-b\C-b\C-b\e\r" }
      assert_screen(<<~EOC)
        Multiline REPL.
        prompt> if true
        prompt>   あ
        prompt>   い
        prompt>   う
        prompt>   え
        prompt>   お
        prompt>
      EOC
      close
    end

    def test_newline_after_wrong_indent
      start_terminal(5, 30, %W{ruby -I#{@pwd}/lib #{@pwd}/test/reline/yamatanooroti/multiline_repl --auto-indent}, startup_message: 'Multiline REPL.')
      write "if 1\n    aa"
      write "\n"
      assert_screen(<<~EOC)
        Multiline REPL.
        prompt> if 1
        prompt>   aa
        prompt>
      EOC
      close
    end

    def test_suppress_auto_indent_just_after_pasted
      start_terminal(5, 30, %W{ruby -I#{@pwd}/lib #{@pwd}/test/reline/yamatanooroti/multiline_repl --auto-indent}, startup_message: 'Multiline REPL.')
      write("def hoge\n  [[\n      3]]\ned")
      write("\C-bn")
      assert_screen(<<~EOC)
        Multiline REPL.
        prompt> def hoge
        prompt>   [[
        prompt>       3]]
        prompt> end
      EOC
      close
    end

    def test_suppress_auto_indent_for_adding_newlines_in_pasting
      start_terminal(5, 30, %W{ruby -I#{@pwd}/lib #{@pwd}/test/reline/yamatanooroti/multiline_repl --auto-indent}, startup_message: 'Multiline REPL.')
      write("<<~Q\n")
      write("{\n  #\n}")
      write("#")
      assert_screen(<<~EOC)
        Multiline REPL.
        prompt> <<~Q
        prompt> {
        prompt>   #
        prompt> }#
      EOC
      close
    end

    def test_auto_indent_with_various_spaces
      start_terminal(5, 30, %W{ruby -I#{@pwd}/lib #{@pwd}/test/reline/yamatanooroti/multiline_repl --auto-indent}, startup_message: 'Multiline REPL.')
      write "(\n\C-v"
      write "\C-k\n\C-v"
      write "\C-k)"
      assert_screen(<<~EOC)
        Multiline REPL.
        prompt> (
        prompt> ^K
        prompt> )
      EOC
      close
    end

    def test_autowrap_in_the_middle_of_a_line
      start_terminal(5, 20, %W{ruby -I#{@pwd}/lib #{@pwd}/test/reline/yamatanooroti/multiline_repl}, startup_message: 'Multiline REPL.')
      write("def abcdefg; end\C-b\C-b\C-b\C-b\C-b")
      %w{h i}.each do |c|
        write(c)
      end
      assert_screen(<<~EOC)
        Multiline REPL.
        prompt> def abcdefgh
        i; end
      EOC
      close
    end

    def test_terminate_in_the_middle_of_lines
      start_terminal(5, 20, %W{ruby -I#{@pwd}/lib #{@pwd}/test/reline/yamatanooroti/multiline_repl}, startup_message: 'Multiline REPL.')
      write("def hoge\n  1\n  2\n  3\n  4\nend\n")
      write("\C-p\C-p\C-p\C-e\n")
      assert_screen(<<~EOC)
        prompt>   3
        prompt>   4
        prompt> end
        => :hoge
        prompt>
      EOC
      close
    end

    def test_dynamic_prompt_returns_empty
      start_terminal(5, 20, %W{ruby -I#{@pwd}/lib #{@pwd}/test/reline/yamatanooroti/multiline_repl --dynamic-prompt-returns-empty}, startup_message: 'Multiline REPL.')
      write("def hoge\nend\n")
      assert_screen(<<~EOC)
        Multiline REPL.
        prompt> def hoge
        prompt> end
        => :hoge
        prompt>
      EOC
      close
    end

    def test_reset_rest_height_when_clear_screen
      start_terminal(5, 20, %W{ruby -I#{@pwd}/lib #{@pwd}/test/reline/yamatanooroti/multiline_repl}, startup_message: 'Multiline REPL.')
      write("\n\n\n\C-l3\n")
      assert_screen(<<~EOC)
        prompt> 3
        => 3
        prompt>
      EOC
      close
    end

    def test_meta_key
      start_terminal(30, 20, %W{ruby -I#{@pwd}/lib #{@pwd}/test/reline/yamatanooroti/multiline_repl}, startup_message: 'Multiline REPL.')
      write("def ge\M-bho")
      assert_screen(<<~EOC)
        Multiline REPL.
        prompt> def hoge
      EOC
      close
    end

    def test_not_meta_key
      start_terminal(5, 30, %W{ruby -I#{@pwd}/lib #{@pwd}/test/reline/yamatanooroti/multiline_repl}, startup_message: 'Multiline REPL.')
      write("おだんご") # "だ" in UTF-8 contains "\xA0"
      assert_screen(<<~EOC)
        Multiline REPL.
        prompt> おだんご
      EOC
      close
    end

    def test_force_enter
      start_terminal(30, 120, %W{ruby -I#{@pwd}/lib #{@pwd}/test/reline/yamatanooroti/multiline_repl}, startup_message: 'Multiline REPL.')
      write("def hoge\nend\C-p\C-e")
      write("\M-\x0D")
      assert_screen(<<~EOC)
        Multiline REPL.
        prompt> def hoge
        prompt>
        prompt> end
      EOC
      close
    end

    def test_nontty
      omit if Reline.core.io_gate.win?
      cmd = %Q{ruby -e 'puts(%Q{ello\C-ah\C-e})' | ruby -I#{@pwd}/lib -rreline -e 'p Reline.readline(%{> })' | ruby -e 'print STDIN.read'}
      start_terminal(40, 50, ['bash', '-c', cmd])
      assert_screen(<<~'EOC')
        > hello
        "hello"
      EOC
      close
    end

    def test_eof_with_newline
      omit if Reline.core.io_gate.win?
      cmd = %Q{ruby -e 'print(%Q{abc def \\e\\r})' | ruby -I#{@pwd}/lib -rreline -e 'p Reline.readline(%{> })'}
      start_terminal(40, 50, ['bash', '-c', cmd])
      assert_screen(<<~'EOC')
        > abc def
        "abc def "
      EOC
      close
    end

    def test_eof_without_newline
      omit if Reline.core.io_gate.win?
      cmd = %Q{ruby -e 'print(%{hello})' | ruby -I#{@pwd}/lib -rreline -e 'p Reline.readline(%{> })'}
      start_terminal(40, 50, ['bash', '-c', cmd])
      assert_screen(<<~'EOC')
        > hello
        "hello"
      EOC
      close
    end

    def test_em_set_mark_and_em_exchange_mark
      start_terminal(10, 50, %W{ruby -I#{@pwd}/lib #{@pwd}/test/reline/yamatanooroti/multiline_repl}, startup_message: 'Multiline REPL.')
      write("aaa bbb ccc ddd\M-b\M-b\M-\x20\M-b\C-x\C-xX\C-x\C-xY")
      assert_screen(<<~'EOC')
        Multiline REPL.
        prompt> aaa Ybbb Xccc ddd
      EOC
      close
    end

    def test_multiline_completion
      start_terminal(10, 50, %W{ruby -I#{@pwd}/lib #{@pwd}/test/reline/yamatanooroti/multiline_repl --complete}, startup_message: 'Multiline REPL.')
      write("def hoge\n  St\n  St\C-p\t")
      assert_screen(<<~'EOC')
        Multiline REPL.
        prompt> def hoge
        prompt>   String
        prompt>   St
      EOC
      close
    end

    def test_completion_journey_2nd_line
      write_inputrc <<~LINES
        set editing-mode vi
      LINES
      start_terminal(10, 50, %W{ruby -I#{@pwd}/lib #{@pwd}/test/reline/yamatanooroti/multiline_repl --complete}, startup_message: 'Multiline REPL.')
      write("def hoge\n  S\C-n")
      assert_screen(<<~'EOC')
        Multiline REPL.
        prompt> def hoge
        prompt>   String
      EOC
      close
    end

    def test_completion_journey_with_empty_line
      write_inputrc <<~LINES
        set editing-mode vi
      LINES
      start_terminal(10, 50, %W{ruby -I#{@pwd}/lib #{@pwd}/test/reline/yamatanooroti/multiline_repl --complete}, startup_message: 'Multiline REPL.')
      write("\C-n\C-p")
      assert_screen(<<~'EOC')
        Multiline REPL.
        prompt>
      EOC
      close
    end

    def test_completion_menu_is_displayed_horizontally
      start_terminal(20, 50, %W{ruby -I#{@pwd}/lib #{@pwd}/test/reline/yamatanooroti/multiline_repl --complete}, startup_message: 'Multiline REPL.')
      write("S\t\t")
      assert_screen(<<~'EOC')
        Multiline REPL.
        prompt> S
        ScriptError  String
        Signal       SyntaxError
      EOC
      close
    end

    def test_show_all_if_ambiguous_on
      write_inputrc <<~LINES
        set show-all-if-ambiguous on
      LINES
      start_terminal(20, 50, %W{ruby -I#{@pwd}/lib #{@pwd}/test/reline/yamatanooroti/multiline_repl --complete}, startup_message: 'Multiline REPL.')
      write("S\t")
      assert_screen(<<~'EOC')
        Multiline REPL.
        prompt> S
        ScriptError  String
        Signal       SyntaxError
      EOC
      close
    end

    def test_show_all_if_ambiguous_on_and_menu_with_perfect_match
      write_inputrc <<~LINES
        set show-all-if-ambiguous on
      LINES
      start_terminal(20, 50, %W{ruby -I#{@pwd}/lib #{@pwd}/test/reline/yamatanooroti/multiline_repl --complete-menu-with-perfect-match}, startup_message: 'Multiline REPL.')
      write("a\t")
      assert_screen(<<~'EOC')
        Multiline REPL.
        prompt> abs
        abs   abs2
      EOC
      close
    end

    def test_simple_dialog
      iterate_over_face_configs do |config_name, config_file|
        start_terminal(20, 50, %W{ruby -I#{@pwd}/lib -r#{config_file.path} #{@pwd}/test/reline/yamatanooroti/multiline_repl --dialog simple}, startup_message: 'Multiline REPL.')
        write('a')
        write('b')
        write('c')
        write("\C-h")
        close
        assert_screen(<<~'EOC', "Failed with `#{config_name}` in Face")
          Multiline REPL.
          prompt> ab
                    Ruby is...
                    A dynamic, open source programming
                    language with a focus on simplicity
                    and productivity. It has an elegant
                    syntax that is natural to read and
                    easy to write.
        EOC
      end
    end

    def test_simple_dialog_at_right_edge
      iterate_over_face_configs do |config_name, config_file|
        start_terminal(20, 40, %W{ruby -I#{@pwd}/lib -r#{config_file.path} #{@pwd}/test/reline/yamatanooroti/multiline_repl --dialog simple}, startup_message: 'Multiline REPL.')
        write('a')
        write('b')
        write('c')
        write("\C-h")
        close
        assert_screen(<<~'EOC')
          Multiline REPL.
          prompt> ab
               Ruby is...
               A dynamic, open source programming
               language with a focus on simplicity
               and productivity. It has an elegant
               syntax that is natural to read and
               easy to write.
        EOC
      end
    end

    def test_dialog_scroll_pushup_condition
      iterate_over_face_configs do |config_name, config_file|
        start_terminal(10, 50, %W{ruby -I#{@pwd}/lib -r#{config_file.path} #{@pwd}/test/reline/yamatanooroti/multiline_repl --autocomplete}, startup_message: 'Multiline REPL.')
        write("\n" * 10)
        write("if 1\n  sSts\nend")
        write("\C-p\C-h\C-e\C-h")
        assert_screen(<<~'EOC')
          prompt>
          prompt>
          prompt>
          prompt>
          prompt>
          prompt>
          prompt> if 1
          prompt>   St
          prompt> enString
                    Struct
        EOC
        close
      end
    end

    def test_simple_dialog_with_scroll_screen
      iterate_over_face_configs do |config_name, config_file|
        start_terminal(5, 50, %W{ruby -I#{@pwd}/lib -r#{config_file.path} #{@pwd}/test/reline/yamatanooroti/multiline_repl --dialog simple}, startup_message: /prompt>/)
        write("if 1\n  2\n  3\n  4\n  5\n  6")
        write("\C-p\C-n\C-p\C-p\C-p#")
        close
        assert_screen(<<~'EOC')
          prompt>   2
          prompt>   3#
          prompt>   4
          prompt>   5 Ruby is...
          prompt>   6 A dynamic, open source programming
        EOC
      end
    end

    def test_autocomplete_at_bottom
      start_terminal(15, 50, %W{ruby -I#{@pwd}/lib #{@pwd}/test/reline/yamatanooroti/multiline_repl --autocomplete}, startup_message: 'Multiline REPL.')
      write('def hoge' + "\C-m" * 10 + "end\C-p  ")
      write('S')
      assert_screen(<<~'EOC')
        Multiline REPL.
        prompt> def hoge
        prompt>
        prompt>
        prompt>   String
        prompt>   Struct
        prompt>   Symbol
        prompt>   ScriptError
        prompt>   SyntaxError
        prompt>   Signal
        prompt>   S
        prompt> end
      EOC
      close
    end

    def test_autocomplete_return_to_original
      start_terminal(20, 20, %W{ruby -I#{@pwd}/lib #{@pwd}/test/reline/yamatanooroti/multiline_repl --autocomplete}, startup_message: 'Multiline REPL.')
      write('S')
      write('t')
      write('r')
      3.times{ write("\C-i") }
      assert_screen(<<~'EOC')
        Multiline REPL.
        prompt> Str
                String
                Struct
      EOC
      close
    end

    def test_autocomplete_target_is_wrapped
      start_terminal(20, 20, %W{ruby -I#{@pwd}/lib #{@pwd}/test/reline/yamatanooroti/multiline_repl --autocomplete}, startup_message: 'Multiline REPL.')
      write('          ')
      write('S')
      write('t')
      write('r')
      assert_screen(<<~'EOC')
        Multiline REPL.
        prompt>           St
        r
        String
        Struct
      EOC
      close
    end

    def test_autocomplete_target_at_end_of_line
      start_terminal(20, 20, %W{ruby -I#{@pwd}/lib #{@pwd}/test/reline/yamatanooroti/multiline_repl --autocomplete}, startup_message: 'Multiline REPL.')
      write('         ')
      write('Str')
      write("\C-i")
      assert_screen(<<~'EOC')
        Multiline REPL.
        prompt>          Str
        ing           String
                      Struct
      EOC
      close
    end

    def test_autocomplete_completed_input_is_wrapped
      start_terminal(20, 20, %W{ruby -I#{@pwd}/lib #{@pwd}/test/reline/yamatanooroti/multiline_repl --autocomplete}, startup_message: 'Multiline REPL.')
      write('        ')
      write('Str')
      write("\C-i")
      assert_screen(<<~'EOC')
        Multiline REPL.
        prompt>         Stri
        ng            String
                      Struct
      EOC
      close
    end

    def test_force_insert_before_autocomplete
      start_terminal(20, 20, %W{ruby -I#{@pwd}/lib #{@pwd}/test/reline/yamatanooroti/multiline_repl --autocomplete}, startup_message: 'Multiline REPL.')
      write('Sy')
      write(";St\t\t")
      assert_screen(<<~'EOC')
        Multiline REPL.
        prompt> Sy;Struct
                   String
                   Struct
      EOC
      close
    end

    def test_simple_dialog_with_scroll_key
      start_terminal(20, 50, %W{ruby -I#{@pwd}/lib #{@pwd}/test/reline/yamatanooroti/multiline_repl --dialog long,scrollkey}, startup_message: 'Multiline REPL.')
      write('a')
      5.times{ write('j') }
      assert_screen(<<~'EOC')
        Multiline REPL.
        prompt> a
                 A dynamic, open
                 source programming
                 language with a
                 focus on simplicity
      EOC
      close
    end

    def test_simple_dialog_scrollbar_with_moving_to_right
      start_terminal(20, 50, %W{ruby -I#{@pwd}/lib #{@pwd}/test/reline/yamatanooroti/multiline_repl --dialog long,scrollkey,scrollbar}, startup_message: 'Multiline REPL.')
      6.times{ write('j') }
      write('a')
      assert_screen(<<~'EOC')
        Multiline REPL.
        prompt> a
                 source programming ▄
                 language with a    █
                 focus on simplicity
                 and productivity.
      EOC
      close
    end

    def test_simple_dialog_scrollbar_with_moving_to_left
      start_terminal(20, 50, %W{ruby -I#{@pwd}/lib #{@pwd}/test/reline/yamatanooroti/multiline_repl --dialog long,scrollkey,scrollbar}, startup_message: 'Multiline REPL.')
      write('a')
      6.times{ write('j') }
      write("\C-h")
      assert_screen(<<~'EOC')
        Multiline REPL.
        prompt>
                source programming ▄
                language with a    █
                focus on simplicity
                and productivity.
      EOC
      close
    end

    def test_dialog_with_fullwidth_chars
      ENV['RELINE_TEST_PROMPT'] = '> '
      start_terminal(20, 5, %W{ruby -I#{@pwd}/lib #{@pwd}/test/reline/yamatanooroti/multiline_repl --dialog fullwidth,scrollkey,scrollbar}, startup_message: 'Multiline REPL.')
      6.times{ write('j') }
      assert_screen(<<~'EOC')
        Multi
        line
        REPL.
        >
        オー
        グ言▄
        備え█
        ち、█
      EOC
      close
    end

    def test_dialog_with_fullwidth_chars_split
      ENV['RELINE_TEST_PROMPT'] = '> '
      start_terminal(20, 6, %W{ruby -I#{@pwd}/lib #{@pwd}/test/reline/yamatanooroti/multiline_repl --dialog fullwidth,scrollkey,scrollbar}, startup_message: 'Multiline REPL.')
      6.times{ write('j') }
      assert_screen(<<~'EOC')
        Multil
        ine RE
        PL.
        >
        オー
        グ言 ▄
        備え █
        ち、 █
      EOC
      close
    end

    def test_autocomplete_empty
      start_terminal(20, 30, %W{ruby -I#{@pwd}/lib #{@pwd}/test/reline/yamatanooroti/multiline_repl --autocomplete}, startup_message: 'Multiline REPL.')
      write('Street')
      assert_screen(<<~'EOC')
        Multiline REPL.
        prompt> Street
      EOC
      close
    end

    def test_autocomplete
      start_terminal(20, 30, %W{ruby -I#{@pwd}/lib #{@pwd}/test/reline/yamatanooroti/multiline_repl --autocomplete}, startup_message: 'Multiline REPL.')
      write('Str')
      assert_screen(<<~'EOC')
        Multiline REPL.
        prompt> Str
                String
                Struct
      EOC
      close
    end

    def test_autocomplete_empty_string
      start_terminal(5, 30, %W{ruby -I#{@pwd}/lib #{@pwd}/test/reline/yamatanooroti/multiline_repl --autocomplete}, startup_message: 'Multiline REPL.')
      write("\C-i")
      assert_screen(<<~'EOC')
        Multiline REPL.
        prompt> String
                String     █
                Struct     ▀
                Symbol
      EOC
      close
    end

    def test_paste_code_with_tab_indent_does_not_fail
      start_terminal(5, 30, %W{ruby -I#{@pwd}/lib #{@pwd}/test/reline/yamatanooroti/multiline_repl --autocomplete-empty}, startup_message: 'Multiline REPL.')
      write("2.times do\n\tputs\n\tputs\nend")
      assert_screen(<<~'EOC')
        Multiline REPL.
        prompt> 2.times do
        prompt> puts
        prompt> puts
        prompt> end
      EOC
      close
    end

    def test_autocomplete_after_2nd_line
      start_terminal(20, 30, %W{ruby -I#{@pwd}/lib #{@pwd}/test/reline/yamatanooroti/multiline_repl --autocomplete}, startup_message: 'Multiline REPL.')
      write("def hoge\n  Str")
      assert_screen(<<~'EOC')
        Multiline REPL.
        prompt> def hoge
        prompt>   Str
                  String
                  Struct
      EOC
      close
    end

    def test_autocomplete_rerender_under_dialog
      start_terminal(20, 30, %W{ruby -I#{@pwd}/lib #{@pwd}/test/reline/yamatanooroti/multiline_repl --autocomplete}, startup_message: 'Multiline REPL.')
      write("def hoge\n\n  123456\n  456789\nend\C-p\C-p\C-p  a = Str")
      write('i')
      assert_screen(<<~'EOC')
        Multiline REPL.
        prompt> def hoge
        prompt>   a = Stri
        prompt>   1234String
        prompt>   456789
        prompt> end
      EOC
      close
    end

    def test_rerender_multiple_dialog
      start_terminal(20, 60, %W{ruby -I#{@pwd}/lib #{@pwd}/test/reline/yamatanooroti/multiline_repl --autocomplete --dialog simple}, startup_message: 'Multiline REPL.')
      write("if\n  abcdef\n  123456\n  456789\nend\C-p\C-p\C-p\C-p Str")
      write("\t")
      assert_screen(<<~'EOC')
        Multiline REPL.
        prompt> if String
        prompt>   aStringRuby is...
        prompt>   1StructA dynamic, open source programming
        prompt>   456789 language with a focus on simplicity
        prompt> end      and productivity. It has an elegant
                         syntax that is natural to read and
                         easy to write.
      EOC
      close
    end

    def test_autocomplete_long_with_scrollbar
      start_terminal(20, 30, %W{ruby -I#{@pwd}/lib #{@pwd}/test/reline/yamatanooroti/multiline_repl --autocomplete-long}, startup_message: 'Multiline REPL.')
      write('S')
      assert_screen(<<~'EOC')
        Multiline REPL.
        prompt> S
                String          █
                Struct          █
                Symbol          █
                StopIteration   █
                SystemCallError █
                SystemExit      █
                SystemStackError█
                ScriptError     █
                SyntaxError     █
                Signal          █
                SizedQueue      █
                Set
                SecureRandom
                Socket
                StringIO
      EOC
      write("\C-i" * 16)
      assert_screen(<<~'EOC')
        Multiline REPL.
        prompt> StringScanner
                Struct          ▄
                Symbol          █
                StopIteration   █
                SystemCallError █
                SystemExit      █
                SystemStackError█
                ScriptError     █
                SyntaxError     █
                Signal          █
                SizedQueue      █
                Set             █
                SecureRandom    ▀
                Socket
                StringIO
                StringScanner
      EOC
      close
    end

    def test_autocomplete_super_long_scroll_to_bottom
      start_terminal(20, 30, %W{ruby -I#{@pwd}/lib #{@pwd}/test/reline/yamatanooroti/multiline_repl --autocomplete-super-long}, startup_message: 'Multiline REPL.')
      shift_tab = [27, 91, 90]
      write('S' + shift_tab.map(&:chr).join)
      assert_screen(<<~'EOC')
        Multiline REPL.
        prompt> Str_BXX
                Str_BXJ
                Str_BXK
                Str_BXL
                Str_BXM
                Str_BXN
                Str_BXO
                Str_BXP
                Str_BXQ
                Str_BXR
                Str_BXS
                Str_BXT
                Str_BXU
                Str_BXV
                Str_BXW
                Str_BXX▄
      EOC
      close
    end

    def test_autocomplete_super_long_and_backspace
      start_terminal(20, 30, %W{ruby -I#{@pwd}/lib #{@pwd}/test/reline/yamatanooroti/multiline_repl --autocomplete-super-long}, startup_message: 'Multiline REPL.')
      shift_tab = [27, 91, 90]
      write('S' + shift_tab.map(&:chr).join)
      write("\C-h")
      assert_screen(<<~'EOC')
        Multiline REPL.
        prompt> Str_BX
                Str_BX █
                Str_BXA█
                Str_BXB█
                Str_BXC█
                Str_BXD█
                Str_BXE█
                Str_BXF█
                Str_BXG█
                Str_BXH█
                Str_BXI
                Str_BXJ
                Str_BXK
                Str_BXL
                Str_BXM
                Str_BXN
      EOC
      close
    end

    def test_dialog_callback_returns_nil
      start_terminal(20, 30, %W{ruby -I#{@pwd}/lib #{@pwd}/test/reline/yamatanooroti/multiline_repl --dialog nil}, startup_message: 'Multiline REPL.')
      write('a')
      assert_screen(<<~'EOC')
        Multiline REPL.
        prompt> a
      EOC
      close
    end

    def test_dialog_narrower_than_screen
      start_terminal(20, 11, %W{ruby -I#{@pwd}/lib #{@pwd}/test/reline/yamatanooroti/multiline_repl --dialog simple}, startup_message: 'Multiline REPL.')
      assert_screen(<<~'EOC')
        Multiline R
        EPL.
        prompt>
        Ruby is...
        A dynamic,
        language wi
        and product
        syntax that
        easy to wri
      EOC
      close
    end

    def test_dialog_narrower_than_screen_with_scrollbar
      start_terminal(20, 11, %W{ruby -I#{@pwd}/lib #{@pwd}/test/reline/yamatanooroti/multiline_repl --autocomplete-long}, startup_message: 'Multiline REPL.')
      write('S' + "\C-i" * 3)
      assert_screen(<<~'EOC')
        Multiline R
        EPL.
        prompt> Sym
        String    █
        Struct    █
        Symbol    █
        StopIterat█
        SystemCall█
        SystemExit█
        SystemStac█
        ScriptErro█
        SyntaxErro█
        Signal    █
        SizedQueue█
        Set
        SecureRand
        Socket
        StringIO
      EOC
      close
    end

    def test_dialog_with_fullwidth_scrollbar
      start_terminal(20, 40, %W{ruby -I#{@pwd}/lib #{@pwd}/test/reline/yamatanooroti/multiline_repl --dialog simple,scrollkey,alt-scrollbar}, startup_message: 'Multiline REPL.')
      assert_screen(<<~'EOC')
        Multiline REPL.
        prompt>
           Ruby is...                         ::
           A dynamic, open source programming ::
           language with a focus on simplicity''
           and productivity. It has an elegant
      EOC
      close
    end

    def test_rerender_argument_prompt_after_pasting
      start_terminal(20, 30, %W{ruby -I#{@pwd}/lib #{@pwd}/test/reline/yamatanooroti/multiline_repl}, startup_message: 'Multiline REPL.')
      write('abcdef')
      write("\M-3\C-h")
      assert_screen(<<~'EOC')
        Multiline REPL.
        prompt> abc
      EOC
      close
    end

    def test_autocomplete_old_dialog_width_greater_than_dialog_width
      start_terminal(40, 40, %W{ruby -I#{@pwd}/lib #{@pwd}/test/reline/yamatanooroti/multiline_repl --autocomplete-width-long}, startup_message: 'Multiline REPL.')
      write("0+ \n12345678901234")
      write("\C-p")
      write("r")
      write("a")
      assert_screen(<<~'EOC')
        Multiline REPL.
        prompt> 0+ ra
        prompt> 123rand 901234
                   raise
      EOC
      close
    end

    def test_scroll_at_bottom_for_dialog
      start_terminal(10, 40, %W{ruby -I#{@pwd}/lib #{@pwd}/test/reline/yamatanooroti/multiline_repl --autocomplete}, startup_message: 'Multiline REPL.')
      write("\n\n\n\n\n\n\n\n\n\n\n")
      write("def hoge\n\nend\C-p\C-e")
      write("  S")
      assert_screen(<<~'EOC')
        prompt>
        prompt>
        prompt>
        prompt>
        prompt>
        prompt> def hoge
        prompt>   S
        prompt> enString     █
                  Struct     ▀
                  Symbol
      EOC
      close
    end

    def test_clear_dialog_in_pasting
      start_terminal(10, 40, %W{ruby -I#{@pwd}/lib #{@pwd}/test/reline/yamatanooroti/multiline_repl --autocomplete}, startup_message: 'Multiline REPL.')
      write("S")
      write("tring ")
      assert_screen(<<~'EOC')
        Multiline REPL.
        prompt> String
      EOC
      close
    end

    def test_prompt_with_newline
      ENV['RELINE_TEST_PROMPT'] = "::\n> "
      start_terminal(5, 30, %W{ruby -I#{@pwd}/lib #{@pwd}/test/reline/yamatanooroti/multiline_repl}, startup_message: 'Multiline REPL.')
      write("def hoge\n  3\nend")
      assert_screen(<<~'EOC')
        Multiline REPL.
        ::\n> def hoge
        ::\n>   3
        ::\n> end
      EOC
      close
    end

    def test_dynamic_prompt_with_newline
      start_terminal(5, 30, %W{ruby -I#{@pwd}/lib #{@pwd}/test/reline/yamatanooroti/multiline_repl --dynamic-prompt-with-newline}, startup_message: 'Multiline REPL.')
      write("def hoge\n  3\nend")
      assert_screen(<<~'EOC')
        Multiline REPL.
        [0000\n]> def hoge
        [0001\n]>   3
        [0001\n]> end
      EOC
      close
    end

    def test_lines_passed_to_dynamic_prompt
      start_terminal(5, 30, %W{ruby -I#{@pwd}/lib #{@pwd}/test/reline/yamatanooroti/multiline_repl --dynamic-prompt-show-line}, startup_message: 'Multiline REPL.')
      write("if true")
      write("\n")
      assert_screen(<<~EOC)
        Multiline REPL.
        [if t]> if true
        [    ]>
      EOC
      close
    end

    def test_clear_dialog_when_just_move_cursor_at_last_line
      start_terminal(10, 30, %W{ruby -I#{@pwd}/lib #{@pwd}/test/reline/yamatanooroti/multiline_repl --autocomplete}, startup_message: 'Multiline REPL.')
      write("class A\n  3\nend\n\n\n")
      write("\C-p\C-p\C-e; S")
      assert_screen(/String/)
      write("\C-n")
      write(";")
      assert_screen(<<~'EOC')
        prompt>   3
        prompt> end
        => 3
        prompt>
        prompt>
        prompt> class A
        prompt>   3; S
        prompt> end;
      EOC
      close
    end

    def test_clear_dialog_when_adding_new_line_to_end_of_buffer
      start_terminal(10, 30, %W{ruby -I#{@pwd}/lib #{@pwd}/test/reline/yamatanooroti/multiline_repl --autocomplete}, startup_message: 'Multiline REPL.')
      write("class A\n  def a\n    3\n    3\n  end\nend")
      write("\n")
      write("class S")
      write("\n")
      write("  3")
      assert_screen(<<~'EOC')
        prompt>   def a
        prompt>     3
        prompt>     3
        prompt>   end
        prompt> end
        => :a
        prompt> class S
        prompt>   3
      EOC
      close
    end

    def test_insert_newline_in_the_middle_of_buffer_just_after_dialog
      start_terminal(10, 30, %W{ruby -I#{@pwd}/lib #{@pwd}/test/reline/yamatanooroti/multiline_repl --autocomplete}, startup_message: 'Multiline REPL.')
      write("class A\n  def a\n    3\n  end\nend")
      write("\n")
      write("\C-p\C-p\C-p\C-p\C-p\C-e\C-hS")
      write("\M-\x0D")
      write("  3")
      assert_screen(<<~'EOC')
        prompt>     3
        prompt>   end
        prompt> end
        => :a
        prompt> class S
        prompt>   3
        prompt>   def a
        prompt>     3
        prompt>   end
        prompt> end
      EOC
      close
    end

    def test_incremental_search_on_not_last_line
      start_terminal(10, 40, %W{ruby -I#{@pwd}/lib #{@pwd}/test/reline/yamatanooroti/multiline_repl --autocomplete}, startup_message: 'Multiline REPL.')
      write("def abc\nend\n")
      write("def def\nend\n")
      write("\C-p\C-p\C-e")
      write("\C-r")
      write("a")
      write("\n\n")
      assert_screen(<<~'EOC')
        prompt> def abc
        prompt> end
        => :abc
        prompt> def def
        prompt> end
        => :def
        prompt> def abc
        prompt> end
        => :abc
        prompt>
      EOC
      close
    end

    def test_bracket_newline_indent
      start_terminal(5, 30, %W{ruby -I#{@pwd}/lib #{@pwd}/test/reline/yamatanooroti/multiline_repl --auto-indent}, startup_message: 'Multiline REPL.')
      write("[\n")
      write("1")
      assert_screen(<<~EOC)
        Multiline REPL.
        prompt> [
        prompt>   1
      EOC
      close
    end

    def test_repeated_input_delete
      start_terminal(5, 30, %W{ruby -I#{@pwd}/lib #{@pwd}/test/reline/yamatanooroti/multiline_repl}, startup_message: 'Multiline REPL.')
      write("a\C-h" * 4000)
      assert_screen(<<~'EOC')
        Multiline REPL.
        prompt>
      EOC
      close
    end

    def test_exit_with_ctrl_d
      start_terminal(5, 30, %W{ruby -I#{@pwd}/lib #{@pwd}/test/reline/yamatanooroti/multiline_repl --auto-indent}, startup_message: 'Multiline REPL.')
      begin
        write("\C-d")
        close
      rescue EOFError
        # EOFError is raised when process terminated.
      end
      assert_screen(<<~EOC)
        Multiline REPL.
        prompt>
      EOC
      close
    end

    def test_print_before_readline
      code = <<~RUBY
        puts 'Multiline REPL.'
        2.times do
          print 'a' * 10
          Reline.readline '>'
        end
      RUBY
      start_terminal(6, 30, ['ruby', "-I#{@pwd}/lib", '-rreline', '-e', code], startup_message: 'Multiline REPL.')
      write "x\n"
      assert_screen(<<~EOC)
        Multiline REPL.
        >x
        >
      EOC
      close
    end

    def test_pre_input_hook_with_redisplay
      code = <<~'RUBY'
        puts 'Multiline REPL.'
        Reline.pre_input_hook = -> do
          Reline.insert_text 'abc'
          Reline.redisplay # Reline doesn't need this but Readline requires calling redisplay
        end
        Reline.readline('prompt> ')
      RUBY
      start_terminal(6, 30, ['ruby', "-I#{@pwd}/lib", '-rreline', '-e', code], startup_message: 'Multiline REPL.')
      assert_screen(<<~EOC)
        Multiline REPL.
        prompt> abc
      EOC
      close
    end

    def test_pre_input_hook_with_multiline_text_insert
      # Frequently used pattern of pre_input_hook
      code = <<~'RUBY'
        puts 'Multiline REPL.'
        Reline.pre_input_hook = -> do
          Reline.insert_text "abc\nef"
        end
        Reline.readline('>')
      RUBY
      start_terminal(6, 30, ['ruby', "-I#{@pwd}/lib", '-rreline', '-e', code], startup_message: 'Multiline REPL.')
      write("\C-ad")
      assert_screen(<<~EOC)
        Multiline REPL.
        >abc
        def
      EOC
      close
    end

    def test_thread_safe
      start_terminal(6, 30, %W{ruby -I#{@pwd}/lib #{@pwd}/test/reline/yamatanooroti/multiline_repl --auto-indent}, startup_message: 'Multiline REPL.')
      write("[Thread.new{Reline.readline'>'},Thread.new{Reline.readmultiline('>'){true}}].map(&:join).size\n")
      write("exit\n")
      write("exit\n")
      write("42\n")
      assert_screen(<<~EOC)
        >exit
        >exit
        => 2
        prompt> 42
        => 42
        prompt>
      EOC
      close
    end

    def test_user_defined_winch
      omit if Reline.core.io_gate.win?
      pidfile = Tempfile.create('pidfile')
      rubyfile = Tempfile.create('rubyfile')
      rubyfile.write <<~RUBY
        File.write(#{pidfile.path.inspect}, Process.pid)
        winch_called = false
        Signal.trap(:WINCH, ->(_arg){ winch_called = true })
        p Reline.readline('>')
        puts "winch: \#{winch_called}"
      RUBY
      rubyfile.close

      start_terminal(10, 50, %W{ruby -I#{@pwd}/lib -rreline #{rubyfile.path}})
      assert_screen(/^>/)
      write 'a'
      assert_screen(/^>a/)
      pid = pidfile.tap(&:rewind).read.to_i
      Process.kill(:WINCH, pid) unless pid.zero?
      write "b\n"
      assert_screen(/"ab"\nwinch: true/)
      close
    ensure
      File.delete(rubyfile.path) if rubyfile
      pidfile.close if pidfile
      File.delete(pidfile.path) if pidfile
    end

    def test_stop_continue
      omit if Reline.core.io_gate.win?
      pidfile = Tempfile.create('pidfile')
      rubyfile = Tempfile.create('rubyfile')
      rubyfile.write <<~RUBY
        File.write(#{pidfile.path.inspect}, Process.pid)
        cont_called = false
        Signal.trap(:CONT, ->(_arg){ cont_called = true })
        Reline.readmultiline('>'){|input| input.match?(/ghi/) }
        puts "cont: \#{cont_called}"
      RUBY
      rubyfile.close
      start_terminal(10, 50, ['bash'])
      write "ruby -I#{@pwd}/lib -rreline #{rubyfile.path}\n"
      assert_screen(/^>/)
      write "abc\ndef\nhi"
      pid = pidfile.tap(&:rewind).read.to_i
      Process.kill(:STOP, pid) unless pid.zero?
      write "fg\n"
      assert_screen(/fg\n.*>/m)
      write "\ebg"
      assert_screen(/>abc\n>def\n>ghi\n/)
      write "\n"
      assert_screen(/cont: true/)
      close
    ensure
      File.delete(rubyfile.path) if rubyfile
      pidfile.close if pidfile
      File.delete(pidfile.path) if pidfile
    end

    def write_inputrc(content)
      File.open(@inputrc_file, 'w') do |f|
        f.write content
      end
    end

    def fold_multiline(str, width)
      str.scan(/.{1,#{width}}/).each(&:rstrip!).join("\n")
    end
  end
rescue LoadError, NameError
  # On Ruby repository, this test suit doesn't run because Ruby repo doesn't
  # have the yamatanooroti gem.
end
