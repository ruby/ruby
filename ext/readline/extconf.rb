require "mkmf"

readline = Struct.new(:headers, :extra_check).new(["stdio.h"])

def readline.have_header(header)
  if super(header, &extra_check)
    headers.push(header)
    return true
  else
    return false
  end
end

def readline.have_var(var)
  return super(var, headers)
end

def readline.have_func(func)
  return super(func, headers)
end

def readline.have_type(type)
  return super(type, headers)
end

dir_config('curses')
dir_config('ncurses')
dir_config('termcap')
dir_config("readline")
enable_libedit = enable_config("libedit")

have_library("user32", nil) if /cygwin/ === RUBY_PLATFORM
have_library("ncurses", "tgetnum") ||
  have_library("termcap", "tgetnum") ||
  have_library("curses", "tgetnum")

case enable_libedit
when true
  # --enable-libedit
  dir_config("libedit")
  unless (readline.have_header("editline/readline.h") ||
          readline.have_header("readline/readline.h")) &&
          have_library("edit", "readline")
    raise "libedit not found"
  end
when false
  # --disable-libedit
  unless ((readline.have_header("readline/readline.h") &&
           readline.have_header("readline/history.h")) &&
           have_library("readline", "readline"))
    raise "readline not found"
  end
else
  # does not specify
  unless ((readline.have_header("readline/readline.h") &&
           readline.have_header("readline/history.h")) &&
           (have_library("readline", "readline") ||
            have_library("edit", "readline"))) ||
            (readline.have_header("editline/readline.h") &&
             have_library("edit", "readline"))
    raise "readline nor libedit not found"
  end
end

readline.have_func("rl_getc")
readline.have_func("rl_getc_function")
readline.have_func("rl_filename_completion_function")
readline.have_func("rl_username_completion_function")
readline.have_func("rl_completion_matches")
readline.have_func("rl_refresh_line")
readline.have_var("rl_deprep_term_function")
readline.have_var("rl_completion_append_character")
readline.have_var("rl_basic_word_break_characters")
readline.have_var("rl_completer_word_break_characters")
readline.have_var("rl_basic_quote_characters")
readline.have_var("rl_completer_quote_characters")
readline.have_var("rl_filename_quote_characters")
readline.have_var("rl_attempted_completion_over")
readline.have_var("rl_library_version")
readline.have_var("rl_editing_mode")
readline.have_var("rl_line_buffer")
readline.have_var("rl_point")
# workaround for native windows.
/mswin|bccwin|mingw/ !~ RUBY_PLATFORM && readline.have_var("rl_event_hook")
/mswin|bccwin|mingw/ !~ RUBY_PLATFORM && readline.have_var("rl_catch_sigwinch")
/mswin|bccwin|mingw/ !~ RUBY_PLATFORM && readline.have_var("rl_catch_signals")
readline.have_var("rl_pre_input_hook")
readline.have_var("rl_special_prefixes")
readline.have_func("rl_cleanup_after_signal")
readline.have_func("rl_free_line_state")
readline.have_func("rl_clear_signals")
readline.have_func("rl_set_screen_size")
readline.have_func("rl_get_screen_size")
readline.have_func("rl_vi_editing_mode")
readline.have_func("rl_emacs_editing_mode")
readline.have_func("replace_history_entry")
readline.have_func("remove_history")
readline.have_func("clear_history")
readline.have_func("rl_redisplay")
readline.have_func("rl_insert_text")
readline.have_func("rl_delete_text")
unless readline.have_type("rl_hook_func_t*")
  $defs << "-Drl_hook_func_t=Function"
end

create_makefile("readline")
