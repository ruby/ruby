require 'fiddle/import'

class Reline::Windows
  RAW_KEYSTROKE_CONFIG = {
    [224, 72] => :ed_prev_history, # ↑
    [224, 80] => :ed_next_history, # ↓
    [224, 77] => :ed_next_char,    # →
    [224, 75] => :ed_prev_char,    # ←
    [224, 83] => :key_delete,      # Del
    [224, 71] => :ed_move_to_beg,  # Home
    [224, 79] => :ed_move_to_end,  # End
    [  0, 41] => :ed_unassigned,   # input method on/off
    [  0, 72] => :ed_prev_history, # ↑
    [  0, 80] => :ed_next_history, # ↓
    [  0, 77] => :ed_next_char,    # →
    [  0, 75] => :ed_prev_char,    # ←
    [  0, 83] => :key_delete,      # Del
    [  0, 71] => :ed_move_to_beg,  # Home
    [  0, 79] => :ed_move_to_end  # End
  }

  if defined? JRUBY_VERSION
    require 'win32api'
  else
    class Win32API
      DLL = {}
      TYPEMAP = {"0" => Fiddle::TYPE_VOID, "S" => Fiddle::TYPE_VOIDP, "I" => Fiddle::TYPE_LONG}
      POINTER_TYPE = Fiddle::SIZEOF_VOIDP == Fiddle::SIZEOF_LONG_LONG ? 'q*' : 'l!*'

      WIN32_TYPES = "VPpNnLlIi"
      DL_TYPES = "0SSI"

      def initialize(dllname, func, import, export = "0", calltype = :stdcall)
        @proto = [import].join.tr(WIN32_TYPES, DL_TYPES).sub(/^(.)0*$/, '\1')
        import = @proto.chars.map {|win_type| TYPEMAP[win_type.tr(WIN32_TYPES, DL_TYPES)]}
        export = TYPEMAP[export.tr(WIN32_TYPES, DL_TYPES)]
        calltype = Fiddle::Importer.const_get(:CALL_TYPE_TO_ABI)[calltype]

        handle = DLL[dllname] ||=
                 begin
                   Fiddle.dlopen(dllname)
                 rescue Fiddle::DLError
                   raise unless File.extname(dllname).empty?
                   Fiddle.dlopen(dllname + ".dll")
                 end

        @func = Fiddle::Function.new(handle[func], import, export, calltype)
      rescue Fiddle::DLError => e
        raise LoadError, e.message, e.backtrace
      end

      def call(*args)
        import = @proto.split("")
        args.each_with_index do |x, i|
          args[i], = [x == 0 ? nil : x].pack("p").unpack(POINTER_TYPE) if import[i] == "S"
          args[i], = [x].pack("I").unpack("i") if import[i] == "I"
        end
        ret, = @func.call(*args)
        return ret || 0
      end
    end
  end

  VK_MENU = 0x12
  VK_SHIFT = 0x10
  STD_INPUT_HANDLE = -10
  STD_OUTPUT_HANDLE = -11
  WINDOW_BUFFER_SIZE_EVENT = 0x04
  @@getwch = Win32API.new('msvcrt', '_getwch', [], 'I')
  @@kbhit = Win32API.new('msvcrt', '_kbhit', [], 'I')
  @@GetKeyState = Win32API.new('user32', 'GetKeyState', ['L'], 'L')
  @@GetConsoleScreenBufferInfo = Win32API.new('kernel32', 'GetConsoleScreenBufferInfo', ['L', 'P'], 'L')
  @@SetConsoleCursorPosition = Win32API.new('kernel32', 'SetConsoleCursorPosition', ['L', 'L'], 'L')
  @@GetStdHandle = Win32API.new('kernel32', 'GetStdHandle', ['L'], 'L')
  @@FillConsoleOutputCharacter = Win32API.new('kernel32', 'FillConsoleOutputCharacter', ['L', 'L', 'L', 'L', 'P'], 'L')
  @@ScrollConsoleScreenBuffer = Win32API.new('kernel32', 'ScrollConsoleScreenBuffer', ['L', 'P', 'P', 'L', 'P'], 'L')
  @@hConsoleHandle = @@GetStdHandle.call(STD_OUTPUT_HANDLE)
  @@hConsoleInputHandle = @@GetStdHandle.call(STD_INPUT_HANDLE)
  @@GetNumberOfConsoleInputEvents = Win32API.new('kernel32', 'GetNumberOfConsoleInputEvents', ['L', 'P'], 'L')
  @@ReadConsoleInput = Win32API.new('kernel32', 'ReadConsoleInput', ['L', 'P', 'L', 'P'], 'L')
  @@input_buf = []
  @@output_buf = []

  def self.getwch
    unless @@input_buf.empty?
      return @@input_buf.shift
    end
    while @@kbhit.call == 0
      sleep(0.001)
    end
    until @@kbhit.call == 0
      ret = @@getwch.call
      if ret == 0 or ret == 0xE0
        @@input_buf << ret
        ret = @@getwch.call
        @@input_buf << ret
        return @@input_buf.shift
      end
      begin
        bytes = ret.chr(Encoding::UTF_8).encode(Encoding.default_external).bytes
        @@input_buf.push(*bytes)
      rescue Encoding::UndefinedConversionError
        @@input_buf << ret
        @@input_buf << @@getwch.call if ret == 224
      end
    end
    @@input_buf.shift
  end

  def self.getc
    num_of_events = 0.chr * 8
    while @@GetNumberOfConsoleInputEvents.(@@hConsoleInputHandle, num_of_events) != 0 and num_of_events.unpack('L').first > 0
      input_record = 0.chr * 18
      read_event = 0.chr * 4
      if @@ReadConsoleInput.(@@hConsoleInputHandle, input_record, 1, read_event) != 0
        event = input_record[0, 2].unpack('s*').first
        if event == WINDOW_BUFFER_SIZE_EVENT
          @@winch_handler.()
        end
      end
    end
    unless @@output_buf.empty?
      return @@output_buf.shift
    end
    input = getwch
    alt = (@@GetKeyState.call(VK_MENU) & 0x80) != 0
    shift_enter = !input.instance_of?(Array) && (@@GetKeyState.call(VK_SHIFT) & 0x80) != 0 && input == 0x0D
    if shift_enter
      # It's treated as Meta+Enter on Windows
      @@output_buf.push("\e".ord)
      @@output_buf.push(input)
    else
      case input
      when 0x00
        alt = false
        @@output_buf.push(input)
        input = getwch
        @@output_buf.push(*input)
      when 0xE0
        @@output_buf.push(input)
        input = getwch
        @@output_buf.push(*input)
      when 0x03
        @@output_buf.push(input)
      else
        @@output_buf.push(input)
      end
    end
    if alt
      "\e".ord
    else
      @@output_buf.shift
    end
  end

  def self.ungetc(c)
    @@output_buf.unshift(c)
  end

  def self.get_screen_size
    csbi = 0.chr * 22
    @@GetConsoleScreenBufferInfo.call(@@hConsoleHandle, csbi)
    csbi[0, 4].unpack('SS').reverse
  end

  def self.cursor_pos
    csbi = 0.chr * 22
    @@GetConsoleScreenBufferInfo.call(@@hConsoleHandle, csbi)
    x = csbi[4, 2].unpack('s*').first
    y = csbi[6, 2].unpack('s*').first
    Reline::CursorPos.new(x, y)
  end

  def self.move_cursor_column(val)
    @@SetConsoleCursorPosition.call(@@hConsoleHandle, cursor_pos.y * 65536 + val)
  end

  def self.move_cursor_up(val)
    if val > 0
      @@SetConsoleCursorPosition.call(@@hConsoleHandle, (cursor_pos.y - val) * 65536 + cursor_pos.x)
    elsif val < 0
      move_cursor_down(-val)
    end
  end

  def self.move_cursor_down(val)
    if val > 0
      @@SetConsoleCursorPosition.call(@@hConsoleHandle, (cursor_pos.y + val) * 65536 + cursor_pos.x)
    elsif val < 0
      move_cursor_up(-val)
    end
  end

  def self.erase_after_cursor
    csbi = 0.chr * 24
    @@GetConsoleScreenBufferInfo.call(@@hConsoleHandle, csbi)
    cursor = csbi[4, 4].unpack('L').first
    written = 0.chr * 4
    @@FillConsoleOutputCharacter.call(@@hConsoleHandle, 0x20, get_screen_size.last - cursor_pos.x, cursor, written)
  end

  def self.scroll_down(val)
    return if val.zero?
    scroll_rectangle = [0, val, get_screen_size.first, get_screen_size.last].pack('s4')
    destination_origin = 0 # y * 65536 + x
    fill = [' '.ord, 0].pack('SS')
    @@ScrollConsoleScreenBuffer.call(@@hConsoleHandle, scroll_rectangle, nil, destination_origin, fill)
  end

  def self.clear_screen
    # TODO: Use FillConsoleOutputCharacter and FillConsoleOutputAttribute
    print "\e[2J"
    print "\e[1;1H"
  end

  def self.set_screen_size(rows, columns)
    raise NotImplementedError
  end

  def self.set_winch_handler(&handler)
    @@winch_handler = handler
  end

  def self.prep
    # do nothing
    nil
  end

  def self.deprep(otio)
    # do nothing
  end
end
