class Reline::ANSI
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
    c = nil
    loop do
      result = select([@@input], [], [], 0.1)
      next if result.nil?
      c = @@input.read(1)
      break
    end
    c&.ord
  end

  def self.ungetc(c)
    @@buf.unshift(c)
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

  def self.prep
    int_handle = Signal.trap('INT', 'IGNORE')
    otio = `stty -g`.chomp
    setting = ' -echo -icrnl cbreak'
    if (`stty -a`.scan(/-parenb\b/).first == '-parenb')
      setting << ' pass8'
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
  end
end
