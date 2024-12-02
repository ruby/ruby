require 'io/wait'

class Reline::Dumb < Reline::IO
  RESET_COLOR = '' # Do not send color reset sequence

  attr_writer :output

  def initialize(encoding: nil)
    @input = STDIN
    @output = STDOUT
    @buf = []
    @pasting = false
    @encoding = encoding
    @screen_size = [24, 80]
  end

  def dumb?
    true
  end

  def encoding
    if @encoding
      @encoding
    elsif RUBY_PLATFORM =~ /mswin|mingw/
      Encoding::UTF_8
    else
      @input.external_encoding || Encoding.default_external
    end
  rescue IOError
    # STDIN.external_encoding raises IOError in Ruby <= 3.0 when STDIN is closed
    Encoding.default_external
  end

  def set_default_key_bindings(_)
  end

  def input=(val)
    @input = val
  end

  def with_raw_input
    yield
  end

  def write(string)
    @output.write(string)
  end

  def buffered_output
    yield
  end

  def getc(_timeout_second)
    unless @buf.empty?
      return @buf.shift
    end
    c = nil
    loop do
      Reline.core.line_editor.handle_signal
      result = @input.wait_readable(0.1)
      next if result.nil?
      c = @input.read(1)
      break
    end
    c&.ord
  end

  def ungetc(c)
    @buf.unshift(c)
  end

  def get_screen_size
    @screen_size
  end

  def cursor_pos
    Reline::CursorPos.new(0, 0)
  end

  def hide_cursor
  end

  def show_cursor
  end

  def move_cursor_column(val)
  end

  def move_cursor_up(val)
  end

  def move_cursor_down(val)
  end

  def erase_after_cursor
  end

  def scroll_down(val)
  end

  def clear_screen
  end

  def set_screen_size(rows, columns)
    @screen_size = [rows, columns]
  end

  def set_winch_handler(&handler)
  end

  def in_pasting?
    @pasting
  end

  def prep
  end

  def deprep(otio)
  end
end
