require 'io/console'

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

    # GNOME
    [27, 79, 72] => :ed_move_to_beg,      # Home
    [27, 79, 70] => :ed_move_to_end,      # End
    # Del is 0x08
    # Arrow keys are the same of KDE

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
  def self.getc
    unless @@buf.empty?
      return @@buf.shift
    end
    c = @@input.raw(intr: true, &:getbyte)
    (c == 0x16 && @@input.raw(min: 0, tim: 0, &:getbyte)) || c
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
      res = +''
      m = nil
      @@input.raw do |stdin|
        @@output << "\e[6n"
        @@output.flush
        while (c = stdin.getc) != 'R'
          res << c if c
        end
        m = res.match(/\e\[(?<row>\d+);(?<column>\d+)/)
        (m.pre_match + m.post_match).chars.reverse_each do |ch|
          stdin.ungetc ch
        end
      end
      column = m[:column].to_i - 1
      row = m[:row].to_i - 1
    rescue Errno::ENOTTY
      buf = @@output.pread(@@output.pos, 0)
      row = buf.count("\n")
      column = buf.rindex("\n") ? (buf.size - buf.rindex("\n")) - 1 : 0
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
