require 'io/console'
require 'timeout'

class Reline::ANSI
  def self.encoding
    Encoding.default_external
  end

  def self.win?
    false
  end

  RAW_KEYSTROKE_CONFIG = {
    # Console (80x25)
    [27, 91, 49, 126] => :ed_move_to_beg, # Home
    [27, 91, 52, 126] => :ed_move_to_end, # End
    [27, 91, 51, 126] => :key_delete,     # Del
    [27, 91, 65] => :ed_prev_history,     # ↑
    [27, 91, 66] => :ed_next_history,     # ↓
    [27, 91, 67] => :ed_next_char,        # →
    [27, 91, 68] => :ed_prev_char,        # ←

    # KDE
    [27, 91, 72] => :ed_move_to_beg,      # Home
    [27, 91, 70] => :ed_move_to_end,      # End
    # Del is 0x08
    [27, 71, 65] => :ed_prev_history,     # ↑
    [27, 71, 66] => :ed_next_history,     # ↓
    [27, 71, 67] => :ed_next_char,        # →
    [27, 71, 68] => :ed_prev_char,        # ←

    # urxvt / exoterm
    [27, 91, 55, 126] => :ed_move_to_beg, # Home
    [27, 91, 56, 126] => :ed_move_to_end, # End

    # GNOME
    [27, 79, 72] => :ed_move_to_beg,      # Home
    [27, 79, 70] => :ed_move_to_end,      # End
    # Del is 0x08
    # Arrow keys are the same of KDE

    # iTerm2
    [27, 27, 91, 67] => :em_next_word,    # Option+→
    [27, 27, 91, 68] => :ed_prev_word,    # Option+←
    [195, 166] => :em_next_word,          # Option+f
    [195, 162] => :ed_prev_word,          # Option+b

    # others
    [27, 32] => :em_set_mark,             # M-<space>
    [24, 24] => :em_exchange_mark,        # C-x C-x TODO also add Windows
    [27, 91, 49, 59, 53, 67] => :em_next_word, # Ctrl+→
    [27, 91, 49, 59, 53, 68] => :ed_prev_word, # Ctrl+←

    [27, 79, 65] => :ed_prev_history,     # ↑
    [27, 79, 66] => :ed_next_history,     # ↓
    [27, 79, 67] => :ed_next_char,        # →
    [27, 79, 68] => :ed_prev_char,        # ←
  }

  @@input = STDIN
  def self.input=(val)
    @@input = val
  end

  @@output = STDOUT
  def self.output=(val)
    @@output = val
  end

  @@buf = []
  def self.inner_getc
    unless @@buf.empty?
      return @@buf.shift
    end
    until c = @@input.raw(intr: true, &:getbyte)
      sleep 0.1
    end
    (c == 0x16 && @@input.raw(min: 0, tim: 0, &:getbyte)) || c
  rescue Errno::EIO
    # Maybe the I/O has been closed.
    nil
  end

  @@in_bracketed_paste_mode = false
  START_BRACKETED_PASTE = String.new("\e[200~,", encoding: Encoding::ASCII_8BIT)
  END_BRACKETED_PASTE = String.new("\e[200~.", encoding: Encoding::ASCII_8BIT)
  def self.getc_with_bracketed_paste
    buffer = String.new(encoding: Encoding::ASCII_8BIT)
    buffer << inner_getc
    while START_BRACKETED_PASTE.start_with?(buffer) or END_BRACKETED_PASTE.start_with?(buffer) do
      if START_BRACKETED_PASTE == buffer
        @@in_bracketed_paste_mode = true
        return inner_getc
      elsif END_BRACKETED_PASTE == buffer
        @@in_bracketed_paste_mode = false
        ungetc(-1)
        return inner_getc
      end
      begin
        succ_c = nil
        Timeout.timeout(Reline.core.config.keyseq_timeout * 100) {
          succ_c = inner_getc
        }
      rescue Timeout::Error
        break
      else
        buffer << succ_c
      end
    end
    buffer.bytes.reverse_each do |ch|
      ungetc ch
    end
    inner_getc
  end

  def self.getc
    if Reline.core.config.enable_bracketed_paste
      getc_with_bracketed_paste
    else
      inner_getc
    end
  end

  def self.in_pasting?
    @@in_bracketed_paste_mode or (not Reline::IOGate.empty_buffer?)
  end

  def self.empty_buffer?
    unless @@buf.empty?
      return false
    end
    rs, = IO.select([@@input], [], [], 0.00001)
    if rs and rs[0]
      false
    else
      true
    end
  end

  def self.ungetc(c)
    @@buf.unshift(c)
  end

  def self.retrieve_keybuffer
    begin
      result = select([@@input], [], [], 0.001)
      return if result.nil?
      str = @@input.read_nonblock(1024)
      str.bytes.each do |c|
        @@buf.push(c)
      end
    rescue EOFError
    end
  end

  def self.get_screen_size
    s = @@input.winsize
    return s if s[0] > 0 && s[1] > 0
    s = [ENV["LINES"].to_i, ENV["COLUMNS"].to_i]
    return s if s[0] > 0 && s[1] > 0
    [24, 80]
  rescue Errno::ENOTTY
    [24, 80]
  end

  def self.set_screen_size(rows, columns)
    @@input.winsize = [rows, columns]
    self
  rescue Errno::ENOTTY
    self
  end

  def self.cursor_pos
    begin
      res = String.new
      m = nil
      @@input.raw do |stdin|
        @@output << "\e[6n"
        @@output.flush
        loop do
          c = stdin.getc
          next if c.nil?
          res << c
          m = res.match(/\e\[(?<row>\d+);(?<column>\d+)R/)
          break if m
        end
        (m.pre_match + m.post_match).chars.reverse_each do |ch|
          stdin.ungetc ch
        end
      end
      column = m[:column].to_i - 1
      row = m[:row].to_i - 1
    rescue Errno::ENOTTY
      begin
        buf = @@output.pread(@@output.pos, 0)
        row = buf.count("\n")
        column = buf.rindex("\n") ? (buf.size - buf.rindex("\n")) - 1 : 0
      rescue Errno::ESPIPE
        # Just returns column 1 for ambiguous width because this I/O is not
        # tty and can't seek.
        row = 0
        column = 1
      end
    end
    Reline::CursorPos.new(column, row)
  end

  def self.move_cursor_column(x)
    @@output.write "\e[#{x + 1}G"
  end

  def self.move_cursor_up(x)
    if x > 0
      @@output.write "\e[#{x}A" if x > 0
    elsif x < 0
      move_cursor_down(-x)
    end
  end

  def self.move_cursor_down(x)
    if x > 0
      @@output.write "\e[#{x}B" if x > 0
    elsif x < 0
      move_cursor_up(-x)
    end
  end

  def self.erase_after_cursor
    @@output.write "\e[K"
  end

  def self.scroll_down(x)
    return if x.zero?
    @@output.write "\e[#{x}S"
  end

  def self.clear_screen
    @@output.write "\e[2J"
    @@output.write "\e[1;1H"
  end

  @@old_winch_handler = nil
  def self.set_winch_handler(&handler)
    @@old_winch_handler = Signal.trap('WINCH', &handler)
  end

  def self.prep
    retrieve_keybuffer
    int_handle = Signal.trap('INT', 'IGNORE')
    Signal.trap('INT', int_handle)
    nil
  end

  def self.deprep(otio)
    int_handle = Signal.trap('INT', 'IGNORE')
    Signal.trap('INT', int_handle)
    Signal.trap('WINCH', @@old_winch_handler) if @@old_winch_handler
  end
end
