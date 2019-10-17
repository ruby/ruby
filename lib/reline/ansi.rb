class Reline::ANSI
  RAW_KEYSTROKE_CONFIG = {
    [27, 91, 65] => :ed_prev_history,     # ↑
    [27, 91, 66] => :ed_next_history,     # ↓
    [27, 91, 67] => :ed_next_char,        # →
    [27, 91, 68] => :ed_prev_char,        # ←
    [27, 91, 51, 126] => :key_delete,     # Del
    [27, 91, 49, 126] => :ed_move_to_beg, # Home
    [27, 91, 52, 126] => :ed_move_to_end, # End
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
    @@input.getbyte
  end

  def self.ungetc(c)
    @@buf.unshift(c)
  end

  def self.retrieve_keybuffer
      result = select([@@input], [], [], 0.001)
      return if result.nil?
      str = @@input.read_nonblock(1024)
      str.bytes.each do |c|
        @@buf.push(c)
      end
  end

  def self.get_screen_size
    @@input.winsize
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
      res = ''
      @@input.raw do |stdin|
        @@output << "\e[6n"
        @@output.flush
        while (c = stdin.getc) != 'R'
          res << c if c
        end
      end
      m = res.match(/(?<row>\d+);(?<column>\d+)/)
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
    print "\e[#{x + 1}G"
  end

  def self.move_cursor_up(x)
    if x > 0
      print "\e[#{x}A" if x > 0
    elsif x < 0
      move_cursor_down(-x)
    end
  end

  def self.move_cursor_down(x)
    if x > 0
      print "\e[#{x}B" if x > 0
    elsif x < 0
      move_cursor_up(-x)
    end
  end

  def self.erase_after_cursor
    print "\e[K"
  end

  def self.scroll_down(x)
    return if x.zero?
    print "\e[#{x}S"
  end

  def self.clear_screen
    print "\e[2J"
    print "\e[1;1H"
  end

  @@old_winch_handler = nil
  def self.set_winch_handler(&handler)
    @@old_winch_handler = Signal.trap('WINCH', &handler)
  end

  def self.prep
    retrieve_keybuffer
    int_handle = Signal.trap('INT', 'IGNORE')
    otio = `stty -g`.chomp
    setting = ' -echo -icrnl cbreak'
    stty = `stty -a`
    if /-parenb\b/ =~ stty
      setting << ' pass8'
    end
    if /\bdsusp *=/ =~ stty
      setting << ' dsusp undef'
    end
    setting << ' -ixoff'
    `stty #{setting}`
    Signal.trap('INT', int_handle)
    otio
  end

  def self.deprep(otio)
    int_handle = Signal.trap('INT', 'IGNORE')
    `stty #{otio}`
    Signal.trap('INT', int_handle)
    Signal.trap('WINCH', @@old_winch_handler) if @@old_winch_handler
  end
end
