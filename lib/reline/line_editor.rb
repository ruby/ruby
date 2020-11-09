require 'reline/kill_ring'
require 'reline/unicode'

require 'tempfile'

class Reline::LineEditor
  # TODO: undo
  attr_reader :line
  attr_reader :byte_pointer
  attr_accessor :confirm_multiline_termination_proc
  attr_accessor :completion_proc
  attr_accessor :completion_append_character
  attr_accessor :output_modifier_proc
  attr_accessor :prompt_proc
  attr_accessor :auto_indent_proc
  attr_accessor :pre_input_hook
  attr_accessor :dig_perfect_match_proc
  attr_writer :output

  VI_MOTIONS = %i{
    ed_prev_char
    ed_next_char
    vi_zero
    ed_move_to_beg
    ed_move_to_end
    vi_to_column
    vi_next_char
    vi_prev_char
    vi_next_word
    vi_prev_word
    vi_to_next_char
    vi_to_prev_char
    vi_end_word
    vi_next_big_word
    vi_prev_big_word
    vi_end_big_word
    vi_repeat_next_char
    vi_repeat_prev_char
  }

  module CompletionState
    NORMAL = :normal
    COMPLETION = :completion
    MENU = :menu
    JOURNEY = :journey
    MENU_WITH_PERFECT_MATCH = :menu_with_perfect_match
    PERFECT_MATCH = :perfect_match
  end

  CompletionJourneyData = Struct.new('CompletionJourneyData', :preposing, :postposing, :list, :pointer)
  MenuInfo = Struct.new('MenuInfo', :target, :list)

  def initialize(config, encoding)
    @config = config
    @completion_append_character = ''
    reset_variables(encoding: encoding)
  end

  def simplified_rendering?
    if finished?
      false
    else
      not @rerender_all and not finished? and Reline::IOGate.in_pasting?
    end
  end

  private def check_multiline_prompt(buffer, prompt)
    if @vi_arg
      prompt = "(arg: #{@vi_arg}) "
      @rerender_all = true
    elsif @searching_prompt
      prompt = @searching_prompt
      @rerender_all = true
    else
      prompt = @prompt
    end
    return [prompt, calculate_width(prompt, true), [prompt] * buffer.size] if simplified_rendering?
    if @prompt_proc
      prompt_list = @prompt_proc.(buffer)
      prompt_list.map!{ prompt } if @vi_arg or @searching_prompt
      if @config.show_mode_in_prompt
        if @config.editing_mode_is?(:vi_command)
          mode_icon = @config.vi_cmd_mode_icon
        elsif @config.editing_mode_is?(:vi_insert)
          mode_icon = @config.vi_ins_mode_icon
        elsif @config.editing_mode_is?(:emacs)
          mode_icon = @config.emacs_mode_string
        else
          mode_icon = '?'
        end
        prompt_list.map!{ |pr| mode_icon + pr }
      end
      prompt = prompt_list[@line_index]
      prompt_width = calculate_width(prompt, true)
      [prompt, prompt_width, prompt_list]
    else
      prompt_width = calculate_width(prompt, true)
      if @config.show_mode_in_prompt
        if @config.editing_mode_is?(:vi_command)
          mode_icon = @config.vi_cmd_mode_icon
        elsif @config.editing_mode_is?(:vi_insert)
          mode_icon = @config.vi_ins_mode_icon
        elsif @config.editing_mode_is?(:emacs)
          mode_icon = @config.emacs_mode_string
        else
          mode_icon = '?'
        end
        prompt = mode_icon + prompt
      end
      [prompt, prompt_width, nil]
    end
  end

  def reset(prompt = '', encoding:)
    @rest_height = (Reline::IOGate.get_screen_size.first - 1) - Reline::IOGate.cursor_pos.y
    @screen_size = Reline::IOGate.get_screen_size
    reset_variables(prompt, encoding: encoding)
    @old_trap = Signal.trap('SIGINT') {
      @old_trap.call if @old_trap.respond_to?(:call) # can also be string, ex: "DEFAULT"
      raise Interrupt
    }
    Reline::IOGate.set_winch_handler do
      @rest_height = (Reline::IOGate.get_screen_size.first - 1) - Reline::IOGate.cursor_pos.y
      old_screen_size = @screen_size
      @screen_size = Reline::IOGate.get_screen_size
      if old_screen_size.last < @screen_size.last # columns increase
        @rerender_all = true
        rerender
      else
        back = 0
        new_buffer = whole_lines
        prompt, prompt_width, prompt_list = check_multiline_prompt(new_buffer, prompt)
        new_buffer.each_with_index do |line, index|
          prompt_width = calculate_width(prompt_list[index], true) if @prompt_proc
          width = prompt_width + calculate_width(line)
          height = calculate_height_by_width(width)
          back += height
        end
        @highest_in_all = back
        @highest_in_this = calculate_height_by_width(prompt_width + @cursor_max)
        @first_line_started_from =
          if @line_index.zero?
            0
          else
            calculate_height_by_lines(@buffer_of_lines[0..(@line_index - 1)], prompt_list || prompt)
          end
        if @prompt_proc
          prompt = prompt_list[@line_index]
          prompt_width = calculate_width(prompt, true)
        end
        calculate_nearest_cursor
        @started_from = calculate_height_by_width(prompt_width + @cursor) - 1
        Reline::IOGate.move_cursor_column((prompt_width + @cursor) % @screen_size.last)
        @highest_in_this = calculate_height_by_width(prompt_width + @cursor_max)
        @rerender_all = true
      end
    end
  end

  def finalize
    Signal.trap('SIGINT', @old_trap)
  end

  def eof?
    @eof
  end

  def reset_variables(prompt = '', encoding:)
    @prompt = prompt
    @mark_pointer = nil
    @encoding = encoding
    @is_multiline = false
    @finished = false
    @cleared = false
    @rerender_all = false
    @history_pointer = nil
    @kill_ring = Reline::KillRing.new
    @vi_clipboard = ''
    @vi_arg = nil
    @waiting_proc = nil
    @waiting_operator_proc = nil
    @completion_journey_data = nil
    @completion_state = CompletionState::NORMAL
    @perfect_matched = nil
    @menu_info = nil
    @first_prompt = true
    @searching_prompt = nil
    @first_char = true
    @eof = false
    @continuous_insertion_buffer = String.new(encoding: @encoding)
    reset_line
  end

  def reset_line
    @cursor = 0
    @cursor_max = 0
    @byte_pointer = 0
    @buffer_of_lines = [String.new(encoding: @encoding)]
    @line_index = 0
    @previous_line_index = nil
    @line = @buffer_of_lines[0]
    @first_line_started_from = 0
    @move_up = 0
    @started_from = 0
    @highest_in_this = 1
    @highest_in_all = 1
    @line_backup_in_history = nil
    @multibyte_buffer = String.new(encoding: 'ASCII-8BIT')
    @check_new_auto_indent = false
  end

  def multiline_on
    @is_multiline = true
  end

  def multiline_off
    @is_multiline = false
  end

  private def calculate_height_by_lines(lines, prompt)
    result = 0
    prompt_list = prompt.is_a?(Array) ? prompt : nil
    lines.each_with_index { |line, i|
      prompt = prompt_list[i] if prompt_list and prompt_list[i]
      result += calculate_height_by_width(calculate_width(prompt, true) + calculate_width(line))
    }
    result
  end

  private def insert_new_line(cursor_line, next_line)
    @line = cursor_line
    @buffer_of_lines.insert(@line_index + 1, String.new(next_line, encoding: @encoding))
    @previous_line_index = @line_index
    @line_index += 1
  end

  private def calculate_height_by_width(width)
    width.div(@screen_size.last) + 1
  end

  private def split_by_width(str, max_width)
    Reline::Unicode.split_by_width(str, max_width, @encoding)
  end

  private def scroll_down(val)
    if val <= @rest_height
      Reline::IOGate.move_cursor_down(val)
      @rest_height -= val
    else
      Reline::IOGate.move_cursor_down(@rest_height)
      Reline::IOGate.scroll_down(val - @rest_height)
      @rest_height = 0
    end
  end

  private def move_cursor_up(val)
    if val > 0
      Reline::IOGate.move_cursor_up(val)
      @rest_height += val
    elsif val < 0
      move_cursor_down(-val)
    end
  end

  private def move_cursor_down(val)
    if val > 0
      Reline::IOGate.move_cursor_down(val)
      @rest_height -= val
      @rest_height = 0 if @rest_height < 0
    elsif val < 0
      move_cursor_up(-val)
    end
  end

  private def calculate_nearest_cursor
    @cursor_max = calculate_width(line)
    new_cursor = 0
    new_byte_pointer = 0
    height = 1
    max_width = @screen_size.last
    if @config.editing_mode_is?(:vi_command)
      last_byte_size = Reline::Unicode.get_prev_mbchar_size(@line, @line.bytesize)
      if last_byte_size > 0
        last_mbchar = @line.byteslice(@line.bytesize - last_byte_size, last_byte_size)
        last_width = Reline::Unicode.get_mbchar_width(last_mbchar)
        cursor_max = @cursor_max - last_width
      else
        cursor_max = @cursor_max
      end
    else
      cursor_max = @cursor_max
    end
    @line.encode(Encoding::UTF_8).grapheme_clusters.each do |gc|
      mbchar_width = Reline::Unicode.get_mbchar_width(gc)
      now = new_cursor + mbchar_width
      if now > cursor_max or now > @cursor
        break
      end
      new_cursor += mbchar_width
      if new_cursor > max_width * height
        height += 1
      end
      new_byte_pointer += gc.bytesize
    end
    @started_from = height - 1
    @cursor = new_cursor
    @byte_pointer = new_byte_pointer
  end

  def rerender_all
    @rerender_all = true
    rerender
  end

  def rerender
    return if @line.nil?
    if @menu_info
      scroll_down(@highest_in_all - @first_line_started_from)
      @rerender_all = true
      @menu_info.list.sort!.each do |item|
        Reline::IOGate.move_cursor_column(0)
        @output.write item
        @output.flush
        scroll_down(1)
      end
      scroll_down(@highest_in_all - 1)
      move_cursor_up(@highest_in_all - 1 - @first_line_started_from)
      @menu_info = nil
    end
    prompt, prompt_width, prompt_list = check_multiline_prompt(whole_lines, prompt)
    if @cleared
      Reline::IOGate.clear_screen
      @cleared = false
      back = 0
      modify_lines(whole_lines).each_with_index do |line, index|
        if @prompt_proc
          pr = prompt_list[index]
          height = render_partial(pr, calculate_width(pr), line, false)
        else
          height = render_partial(prompt, prompt_width, line, false)
        end
        if index < (@buffer_of_lines.size - 1)
          move_cursor_down(height)
          back += height
        end
      end
      move_cursor_up(back)
      move_cursor_down(@first_line_started_from + @started_from)
      Reline::IOGate.move_cursor_column((prompt_width + @cursor) % @screen_size.last)
      return
    end
    new_highest_in_this = calculate_height_by_width(prompt_width + calculate_width(@line.nil? ? '' : @line))
    # FIXME: end of logical line sometimes breaks
    if @previous_line_index or new_highest_in_this != @highest_in_this
      if @previous_line_index
        new_lines = whole_lines(index: @previous_line_index, line: @line)
      else
        new_lines = whole_lines
      end
      prompt, prompt_width, prompt_list = check_multiline_prompt(new_lines, prompt)
      all_height = calculate_height_by_lines(new_lines, prompt_list || prompt)
      diff = all_height - @highest_in_all
      move_cursor_down(@highest_in_all - @first_line_started_from - @started_from - 1)
      if diff > 0
        scroll_down(diff)
        move_cursor_up(all_height - 1)
      elsif diff < 0
        (-diff).times do
          Reline::IOGate.move_cursor_column(0)
          Reline::IOGate.erase_after_cursor
          move_cursor_up(1)
        end
        move_cursor_up(all_height - 1)
      else
        move_cursor_up(all_height - 1)
      end
      @highest_in_all = all_height
      back = 0
      modify_lines(new_lines).each_with_index do |line, index|
        if @prompt_proc
          prompt = prompt_list[index]
          prompt_width = calculate_width(prompt, true)
        end
        height = render_partial(prompt, prompt_width, line, false)
        if index < (new_lines.size - 1)
          scroll_down(1)
          back += height
        else
          back += height - 1
        end
      end
      move_cursor_up(back)
      if @previous_line_index
        @buffer_of_lines[@previous_line_index] = @line
        @line = @buffer_of_lines[@line_index]
      end
      @first_line_started_from =
        if @line_index.zero?
          0
        else
          calculate_height_by_lines(@buffer_of_lines[0..(@line_index - 1)], prompt_list || prompt)
        end
      if @prompt_proc
        prompt = prompt_list[@line_index]
        prompt_width = calculate_width(prompt, true)
      end
      move_cursor_down(@first_line_started_from)
      calculate_nearest_cursor
      @started_from = calculate_height_by_width(prompt_width + @cursor) - 1
      move_cursor_down(@started_from)
      Reline::IOGate.move_cursor_column((prompt_width + @cursor) % @screen_size.last)
      @highest_in_this = calculate_height_by_width(prompt_width + @cursor_max)
      @previous_line_index = nil
      rendered = true
    elsif @rerender_all
      move_cursor_up(@first_line_started_from + @started_from)
      Reline::IOGate.move_cursor_column(0)
      back = 0
      new_buffer = whole_lines
      prompt, prompt_width, prompt_list = check_multiline_prompt(new_buffer, prompt)
      new_buffer.each_with_index do |line, index|
        prompt_width = calculate_width(prompt_list[index], true) if @prompt_proc
        width = prompt_width + calculate_width(line)
        height = calculate_height_by_width(width)
        back += height
      end
      if back > @highest_in_all
        scroll_down(back - 1)
        move_cursor_up(back - 1)
      elsif back < @highest_in_all
        scroll_down(back)
        Reline::IOGate.erase_after_cursor
        (@highest_in_all - back - 1).times do
          scroll_down(1)
          Reline::IOGate.erase_after_cursor
        end
        move_cursor_up(@highest_in_all - 1)
      end
      modify_lines(new_buffer).each_with_index do |line, index|
        if @prompt_proc
          prompt = prompt_list[index]
          prompt_width = calculate_width(prompt, true)
        end
        render_partial(prompt, prompt_width, line, false)
        if index < (new_buffer.size - 1)
          move_cursor_down(1)
        end
      end
      move_cursor_up(back - 1)
      if @prompt_proc
        prompt = prompt_list[@line_index]
        prompt_width = calculate_width(prompt, true)
      end
      @highest_in_all = back
      @highest_in_this = calculate_height_by_width(prompt_width + @cursor_max)
      @first_line_started_from =
        if @line_index.zero?
          0
        else
          calculate_height_by_lines(new_buffer[0..(@line_index - 1)], prompt_list || prompt)
        end
      @started_from = calculate_height_by_width(prompt_width + @cursor) - 1
      move_cursor_down(@first_line_started_from + @started_from)
      Reline::IOGate.move_cursor_column((prompt_width + @cursor) % @screen_size.last)
      @rerender_all = false
      rendered = true
    end
    line = modify_lines(whole_lines)[@line_index]
    if @is_multiline
      prompt, prompt_width, prompt_list = check_multiline_prompt(whole_lines, prompt)
      if finished?
        # Always rerender on finish because output_modifier_proc may return a different output.
        render_partial(prompt, prompt_width, line)
        scroll_down(1)
        Reline::IOGate.move_cursor_column(0)
        Reline::IOGate.erase_after_cursor
      elsif not rendered
        render_partial(prompt, prompt_width, line)
      end
    else
      render_partial(prompt, prompt_width, line)
      if finished?
        scroll_down(1)
        Reline::IOGate.move_cursor_column(0)
        Reline::IOGate.erase_after_cursor
      end
    end
  end

  private def render_partial(prompt, prompt_width, line_to_render, with_control = true)
    visual_lines, height = split_by_width(line_to_render.nil? ? prompt : prompt + line_to_render, @screen_size.last)
    if with_control
      if height > @highest_in_this
        diff = height - @highest_in_this
        scroll_down(diff)
        @highest_in_all += diff
        @highest_in_this = height
        move_cursor_up(diff)
      elsif height < @highest_in_this
        diff = @highest_in_this - height
        @highest_in_all -= diff
        @highest_in_this = height
      end
      move_cursor_up(@started_from)
      @started_from = calculate_height_by_width(prompt_width + @cursor) - 1
    end
    Reline::IOGate.move_cursor_column(0)
    visual_lines.each_with_index do |line, index|
      if line.nil?
        if calculate_width(visual_lines[index - 1], true) == Reline::IOGate.get_screen_size.last
          # reaches the end of line
          if Reline::IOGate.win?
            # A newline is automatically inserted if a character is rendered at
            # eol on command prompt.
          else
            # When the cursor is at the end of the line and erases characters
            # after the cursor, some terminals delete the character at the
            # cursor position.
            move_cursor_down(1)
            Reline::IOGate.move_cursor_column(0)
          end
        else
          Reline::IOGate.erase_after_cursor
          move_cursor_down(1)
          Reline::IOGate.move_cursor_column(0)
        end
        next
      end
      @output.write line
      if Reline::IOGate.win? and calculate_width(line, true) == Reline::IOGate.get_screen_size.last
        # A newline is automatically inserted if a character is rendered at eol on command prompt.
        @rest_height -= 1 if @rest_height > 0
      end
      @output.flush
      if @first_prompt
        @first_prompt = false
        @pre_input_hook&.call
      end
    end
    Reline::IOGate.erase_after_cursor
    Reline::IOGate.move_cursor_column(0)
    if with_control
      # Just after rendring, so the cursor is on the last line.
      if finished?
        Reline::IOGate.move_cursor_column(0)
      else
        # Moves up from bottom of lines to the cursor position.
        move_cursor_up(height - 1 - @started_from)
        Reline::IOGate.move_cursor_column((prompt_width + @cursor) % @screen_size.last)
      end
    end
    height
  end

  private def modify_lines(before)
    return before if before.nil? || before.empty? || simplified_rendering?

    if after = @output_modifier_proc&.call("#{before.join("\n")}\n", complete: finished?)
      after.lines("\n").map { |l| l.chomp('') }
    else
      before
    end
  end

  def editing_mode
    @config.editing_mode
  end

  private def menu(target, list)
    @menu_info = MenuInfo.new(target, list)
  end

  private def complete_internal_proc(list, is_menu)
    preposing, target, postposing = retrieve_completion_block
    list = list.select { |i|
      if i and not Encoding.compatible?(target.encoding, i.encoding)
        raise Encoding::CompatibilityError, "#{target.encoding.name} is not compatible with #{i.encoding.name}"
      end
      if @config.completion_ignore_case
        i&.downcase&.start_with?(target.downcase)
      else
        i&.start_with?(target)
      end
    }.uniq
    if is_menu
      menu(target, list)
      return nil
    end
    completed = list.inject { |memo, item|
      begin
        memo_mbchars = memo.unicode_normalize.grapheme_clusters
        item_mbchars = item.unicode_normalize.grapheme_clusters
      rescue Encoding::CompatibilityError
        memo_mbchars = memo.grapheme_clusters
        item_mbchars = item.grapheme_clusters
      end
      size = [memo_mbchars.size, item_mbchars.size].min
      result = ''
      size.times do |i|
        if @config.completion_ignore_case
          if memo_mbchars[i].casecmp?(item_mbchars[i])
            result << memo_mbchars[i]
          else
            break
          end
        else
          if memo_mbchars[i] == item_mbchars[i]
            result << memo_mbchars[i]
          else
            break
          end
        end
      end
      result
    }
    [target, preposing, completed, postposing]
  end

  private def complete(list, just_show_list = false)
    case @completion_state
    when CompletionState::NORMAL, CompletionState::JOURNEY
      @completion_state = CompletionState::COMPLETION
    when CompletionState::PERFECT_MATCH
      @dig_perfect_match_proc&.(@perfect_matched)
    end
    if just_show_list
      is_menu = true
    elsif @completion_state == CompletionState::MENU
      is_menu = true
    elsif @completion_state == CompletionState::MENU_WITH_PERFECT_MATCH
      is_menu = true
    else
      is_menu = false
    end
    result = complete_internal_proc(list, is_menu)
    if @completion_state == CompletionState::MENU_WITH_PERFECT_MATCH
      @completion_state = CompletionState::PERFECT_MATCH
    end
    return if result.nil?
    target, preposing, completed, postposing = result
    return if completed.nil?
    if target <= completed and (@completion_state == CompletionState::COMPLETION)
      if list.include?(completed)
        if list.one?
          @completion_state = CompletionState::PERFECT_MATCH
        else
          @completion_state = CompletionState::MENU_WITH_PERFECT_MATCH
        end
        @perfect_matched = completed
      else
        @completion_state = CompletionState::MENU
      end
      if not just_show_list and target < completed
        @line = preposing + completed + completion_append_character.to_s + postposing
        line_to_pointer = preposing + completed + completion_append_character.to_s
        @cursor_max = calculate_width(@line)
        @cursor = calculate_width(line_to_pointer)
        @byte_pointer = line_to_pointer.bytesize
      end
    end
  end

  private def move_completed_list(list, direction)
    case @completion_state
    when CompletionState::NORMAL, CompletionState::COMPLETION,
         CompletionState::MENU, CompletionState::MENU_WITH_PERFECT_MATCH
      @completion_state = CompletionState::JOURNEY
      result = retrieve_completion_block
      return if result.nil?
      preposing, target, postposing = result
      @completion_journey_data = CompletionJourneyData.new(
        preposing, postposing,
        [target] + list.select{ |item| item.start_with?(target) }, 0)
      @completion_state = CompletionState::JOURNEY
    else
      case direction
      when :up
        @completion_journey_data.pointer -= 1
        if @completion_journey_data.pointer < 0
          @completion_journey_data.pointer = @completion_journey_data.list.size - 1
        end
      when :down
        @completion_journey_data.pointer += 1
        if @completion_journey_data.pointer >= @completion_journey_data.list.size
          @completion_journey_data.pointer = 0
        end
      end
      completed = @completion_journey_data.list[@completion_journey_data.pointer]
      @line = @completion_journey_data.preposing + completed + @completion_journey_data.postposing
      line_to_pointer = @completion_journey_data.preposing + completed
      @cursor_max = calculate_width(@line)
      @cursor = calculate_width(line_to_pointer)
      @byte_pointer = line_to_pointer.bytesize
    end
  end

  private def run_for_operators(key, method_symbol, &block)
    if @waiting_operator_proc
      if VI_MOTIONS.include?(method_symbol)
        old_cursor, old_byte_pointer = @cursor, @byte_pointer
        block.(true)
        unless @waiting_proc
          cursor_diff, byte_pointer_diff = @cursor - old_cursor, @byte_pointer - old_byte_pointer
          @cursor, @byte_pointer = old_cursor, old_byte_pointer
          @waiting_operator_proc.(cursor_diff, byte_pointer_diff)
        else
          old_waiting_proc = @waiting_proc
          old_waiting_operator_proc = @waiting_operator_proc
          current_waiting_operator_proc = @waiting_operator_proc
          @waiting_proc = proc { |k|
            old_cursor, old_byte_pointer = @cursor, @byte_pointer
            old_waiting_proc.(k)
            cursor_diff, byte_pointer_diff = @cursor - old_cursor, @byte_pointer - old_byte_pointer
            @cursor, @byte_pointer = old_cursor, old_byte_pointer
            current_waiting_operator_proc.(cursor_diff, byte_pointer_diff)
            @waiting_operator_proc = old_waiting_operator_proc
          }
        end
      else
        # Ignores operator when not motion is given.
        block.(false)
      end
      @waiting_operator_proc = nil
    else
      block.(false)
    end
  end

  private def argumentable?(method_obj)
    method_obj and method_obj.parameters.any? { |param| param[0] == :key and param[1] == :arg }
  end

  private def inclusive?(method_obj)
    # If a motion method with the keyword argument "inclusive" follows the
    # operator, it must contain the character at the cursor position.
    method_obj and method_obj.parameters.any? { |param| param[0] == :key and param[1] == :inclusive }
  end

  def wrap_method_call(method_symbol, method_obj, key, with_operator = false)
    if @config.editing_mode_is?(:emacs, :vi_insert) and @waiting_proc.nil? and @waiting_operator_proc.nil?
      not_insertion = method_symbol != :ed_insert
      process_insert(force: not_insertion)
    end
    if @vi_arg and argumentable?(method_obj)
      if with_operator and inclusive?(method_obj)
        method_obj.(key, arg: @vi_arg, inclusive: true)
      else
        method_obj.(key, arg: @vi_arg)
      end
    else
      if with_operator and inclusive?(method_obj)
        method_obj.(key, inclusive: true)
      else
        method_obj.(key)
      end
    end
  end

  private def process_key(key, method_symbol)
    if method_symbol and respond_to?(method_symbol, true)
      method_obj = method(method_symbol)
    else
      method_obj = nil
    end
    if method_symbol and key.is_a?(Symbol)
      if @vi_arg and argumentable?(method_obj)
        run_for_operators(key, method_symbol) do |with_operator|
          wrap_method_call(method_symbol, method_obj, key, with_operator)
        end
      else
        wrap_method_call(method_symbol, method_obj, key) if method_obj
      end
      @kill_ring.process
      @vi_arg = nil
    elsif @vi_arg
      if key.chr =~ /[0-9]/
        ed_argument_digit(key)
      else
        if argumentable?(method_obj)
          run_for_operators(key, method_symbol) do |with_operator|
            wrap_method_call(method_symbol, method_obj, key, with_operator)
          end
        elsif @waiting_proc
          @waiting_proc.(key)
        elsif method_obj
          wrap_method_call(method_symbol, method_obj, key)
        else
          ed_insert(key) unless @config.editing_mode_is?(:vi_command)
        end
        @kill_ring.process
        @vi_arg = nil
      end
    elsif @waiting_proc
      @waiting_proc.(key)
      @kill_ring.process
    elsif method_obj
      if method_symbol == :ed_argument_digit
        wrap_method_call(method_symbol, method_obj, key)
      else
        run_for_operators(key, method_symbol) do |with_operator|
          wrap_method_call(method_symbol, method_obj, key, with_operator)
        end
      end
      @kill_ring.process
    else
      ed_insert(key) unless @config.editing_mode_is?(:vi_command)
    end
  end

  private def normal_char(key)
    method_symbol = method_obj = nil
    if key.combined_char.is_a?(Symbol)
      process_key(key.combined_char, key.combined_char)
      return
    end
    @multibyte_buffer << key.combined_char
    if @multibyte_buffer.size > 1
      if @multibyte_buffer.dup.force_encoding(@encoding).valid_encoding?
        process_key(@multibyte_buffer.dup.force_encoding(@encoding), nil)
        @multibyte_buffer.clear
      else
        # invalid
        return
      end
    else # single byte
      return if key.char >= 128 # maybe, first byte of multi byte
      method_symbol = @config.editing_mode.get_method(key.combined_char)
      if key.with_meta and method_symbol == :ed_unassigned
        # split ESC + key
        method_symbol = @config.editing_mode.get_method("\e".ord)
        process_key("\e".ord, method_symbol)
        method_symbol = @config.editing_mode.get_method(key.char)
        process_key(key.char, method_symbol)
      else
        process_key(key.combined_char, method_symbol)
      end
      @multibyte_buffer.clear
    end
    if @config.editing_mode_is?(:vi_command) and @cursor > 0 and @cursor == @cursor_max
      byte_size = Reline::Unicode.get_prev_mbchar_size(@line, @byte_pointer)
      @byte_pointer -= byte_size
      mbchar = @line.byteslice(@byte_pointer, byte_size)
      width = Reline::Unicode.get_mbchar_width(mbchar)
      @cursor -= width
    end
  end

  def input_key(key)
    if key.char.nil?
      if @first_char
        @line = nil
      end
      finish
      return
    end
    @first_char = false
    completion_occurs = false
    if @config.editing_mode_is?(:emacs, :vi_insert) and key.char == "\C-i".ord
      unless @config.disable_completion
        result = call_completion_proc
        if result.is_a?(Array)
          completion_occurs = true
          process_insert
          complete(result)
        end
      end
    elsif not @config.disable_completion and @config.editing_mode_is?(:vi_insert) and ["\C-p".ord, "\C-n".ord].include?(key.char)
      unless @config.disable_completion
        result = call_completion_proc
        if result.is_a?(Array)
          completion_occurs = true
          process_insert
          move_completed_list(result, "\C-p".ord == key.char ? :up : :down)
        end
      end
    elsif Symbol === key.char and respond_to?(key.char, true)
      process_key(key.char, key.char)
    else
      normal_char(key)
    end
    unless completion_occurs
      @completion_state = CompletionState::NORMAL
    end
    if @is_multiline and @auto_indent_proc and not simplified_rendering?
      process_auto_indent
    end
  end

  def call_completion_proc
    result = retrieve_completion_block(true)
    slice = result[1]
    result = @completion_proc.(slice) if @completion_proc and slice
    Reline.core.instance_variable_set(:@completion_quote_character, nil)
    result
  end

  private def process_auto_indent
    return if not @check_new_auto_indent and @previous_line_index # move cursor up or down
    if @check_new_auto_indent and @previous_line_index and @previous_line_index > 0 and @line_index > @previous_line_index
      # Fix indent of a line when a newline is inserted to the next
      new_lines = whole_lines(index: @previous_line_index, line: @line)
      new_indent = @auto_indent_proc.(new_lines[0..-3].push(''), @line_index - 1, 0, true)
      md = @line.match(/\A */)
      prev_indent = md[0].count(' ')
      @line = ' ' * new_indent + @line.lstrip

      new_indent = nil
      result = @auto_indent_proc.(new_lines[0..-2], @line_index - 1, (new_lines[-2].size + 1), false)
      if result
        new_indent = result
      end
      if new_indent&.>= 0
        @line = ' ' * new_indent + @line.lstrip
      end
    end
    if @previous_line_index
      new_lines = whole_lines(index: @previous_line_index, line: @line)
    else
      new_lines = whole_lines
    end
    new_indent = @auto_indent_proc.(new_lines, @line_index, @byte_pointer, @check_new_auto_indent)
    if new_indent&.>= 0
      md = new_lines[@line_index].match(/\A */)
      prev_indent = md[0].count(' ')
      if @check_new_auto_indent
        @buffer_of_lines[@line_index] = ' ' * new_indent + @buffer_of_lines[@line_index].lstrip
        @cursor = new_indent
        @byte_pointer = new_indent
      else
        @line = ' ' * new_indent + @line.lstrip
        @cursor += new_indent - prev_indent
        @byte_pointer += new_indent - prev_indent
      end
    end
    @check_new_auto_indent = false
  end

  def retrieve_completion_block(set_completion_quote_character = false)
    word_break_regexp = /\A[#{Regexp.escape(Reline.completer_word_break_characters)}]/
    quote_characters_regexp = /\A[#{Regexp.escape(Reline.completer_quote_characters)}]/
    before = @line.byteslice(0, @byte_pointer)
    rest = nil
    break_pointer = nil
    quote = nil
    closing_quote = nil
    escaped_quote = nil
    i = 0
    while i < @byte_pointer do
      slice = @line.byteslice(i, @byte_pointer - i)
      unless slice.valid_encoding?
        i += 1
        next
      end
      if quote and slice.start_with?(closing_quote)
        quote = nil
        i += 1
        rest = nil
      elsif quote and slice.start_with?(escaped_quote)
        # skip
        i += 2
      elsif slice =~ quote_characters_regexp # find new "
        rest = $'
        quote = $&
        closing_quote = /(?!\\)#{Regexp.escape(quote)}/
        escaped_quote = /\\#{Regexp.escape(quote)}/
        i += 1
        break_pointer = i - 1
      elsif not quote and slice =~ word_break_regexp
        rest = $'
        i += 1
        before = @line.byteslice(i, @byte_pointer - i)
        break_pointer = i
      else
        i += 1
      end
    end
    postposing = @line.byteslice(@byte_pointer, @line.bytesize - @byte_pointer)
    if rest
      preposing = @line.byteslice(0, break_pointer)
      target = rest
      if set_completion_quote_character and quote
        Reline.core.instance_variable_set(:@completion_quote_character, quote)
        if postposing !~ /(?!\\)#{Regexp.escape(quote)}/ # closing quote
          insert_text(quote)
        end
      end
    else
      preposing = ''
      if break_pointer
        preposing = @line.byteslice(0, break_pointer)
      else
        preposing = ''
      end
      target = before
    end
    [preposing.encode(@encoding), target.encode(@encoding), postposing.encode(@encoding)]
  end

  def confirm_multiline_termination
    temp_buffer = @buffer_of_lines.dup
    if @previous_line_index and @line_index == (@buffer_of_lines.size - 1)
      temp_buffer[@previous_line_index] = @line
    else
      temp_buffer[@line_index] = @line
    end
    @confirm_multiline_termination_proc.(temp_buffer.join("\n") + "\n")
  end

  def insert_text(text)
    width = calculate_width(text)
    if @cursor == @cursor_max
      @line += text
    else
      @line = byteinsert(@line, @byte_pointer, text)
    end
    @byte_pointer += text.bytesize
    @cursor += width
    @cursor_max += width
  end

  def delete_text(start = nil, length = nil)
    if start.nil? and length.nil?
      @line&.clear
      @byte_pointer = 0
      @cursor = 0
      @cursor_max = 0
    elsif not start.nil? and not length.nil?
      if @line
        before = @line.byteslice(0, start)
        after = @line.byteslice(start + length, @line.bytesize)
        @line = before + after
        @byte_pointer = @line.bytesize if @byte_pointer > @line.bytesize
        str = @line.byteslice(0, @byte_pointer)
        @cursor = calculate_width(str)
        @cursor_max = calculate_width(@line)
      end
    elsif start.is_a?(Range)
      range = start
      first = range.first
      last = range.last
      last = @line.bytesize - 1 if last > @line.bytesize
      last += @line.bytesize if last < 0
      first += @line.bytesize if first < 0
      range = range.exclude_end? ? first...last : first..last
      @line = @line.bytes.reject.with_index{ |c, i| range.include?(i) }.map{ |c| c.chr(Encoding::ASCII_8BIT) }.join.force_encoding(@encoding)
      @byte_pointer = @line.bytesize if @byte_pointer > @line.bytesize
      str = @line.byteslice(0, @byte_pointer)
      @cursor = calculate_width(str)
      @cursor_max = calculate_width(@line)
    else
      @line = @line.byteslice(0, start)
      @byte_pointer = @line.bytesize if @byte_pointer > @line.bytesize
      str = @line.byteslice(0, @byte_pointer)
      @cursor = calculate_width(str)
      @cursor_max = calculate_width(@line)
    end
  end

  def byte_pointer=(val)
    @byte_pointer = val
    str = @line.byteslice(0, @byte_pointer)
    @cursor = calculate_width(str)
    @cursor_max = calculate_width(@line)
  end

  def whole_lines(index: @line_index, line: @line)
    temp_lines = @buffer_of_lines.dup
    temp_lines[index] = line
    temp_lines
  end

  def whole_buffer
    if @buffer_of_lines.size == 1 and @line.nil?
      nil
    else
      whole_lines.join("\n")
    end
  end

  def finished?
    @finished
  end

  def finish
    @finished = true
    @rerender_all = true
    @config.reset
  end

  private def byteslice!(str, byte_pointer, size)
    new_str = str.byteslice(0, byte_pointer)
    new_str << str.byteslice(byte_pointer + size, str.bytesize)
    [new_str, str.byteslice(byte_pointer, size)]
  end

  private def byteinsert(str, byte_pointer, other)
    new_str = str.byteslice(0, byte_pointer)
    new_str << other
    new_str << str.byteslice(byte_pointer, str.bytesize)
    new_str
  end

  private def calculate_width(str, allow_escape_code = false)
    Reline::Unicode.calculate_width(str, allow_escape_code)
  end

  private def key_delete(key)
    if @config.editing_mode_is?(:vi_insert, :emacs)
      ed_delete_next_char(key)
    end
  end

  private def key_newline(key)
    if @is_multiline
      next_line = @line.byteslice(@byte_pointer, @line.bytesize - @byte_pointer)
      cursor_line = @line.byteslice(0, @byte_pointer)
      insert_new_line(cursor_line, next_line)
      @cursor = 0
      @check_new_auto_indent = true
    end
  end

  private def ed_unassigned(key) end # do nothing

  private def process_insert(force: false)
    return if @continuous_insertion_buffer.empty? or (Reline::IOGate.in_pasting? and not force)
    width = Reline::Unicode.calculate_width(@continuous_insertion_buffer)
    bytesize = @continuous_insertion_buffer.bytesize
    if @cursor == @cursor_max
      @line += @continuous_insertion_buffer
    else
      @line = byteinsert(@line, @byte_pointer, @continuous_insertion_buffer)
    end
    @byte_pointer += bytesize
    @cursor += width
    @cursor_max += width
    @continuous_insertion_buffer.clear
  end

  private def ed_insert(key)
    str = nil
    width = nil
    bytesize = nil
    if key.instance_of?(String)
      begin
        key.encode(Encoding::UTF_8)
      rescue Encoding::UndefinedConversionError
        return
      end
      str = key
      bytesize = key.bytesize
    else
      begin
        key.chr.encode(Encoding::UTF_8)
      rescue Encoding::UndefinedConversionError
        return
      end
      str = key.chr
      bytesize = 1
    end
    if Reline::IOGate.in_pasting?
      @continuous_insertion_buffer << str
      return
    elsif not @continuous_insertion_buffer.empty?
      process_insert
    end
    width = Reline::Unicode.get_mbchar_width(str)
    if @cursor == @cursor_max
      @line += str
    else
      @line = byteinsert(@line, @byte_pointer, str)
    end
    @byte_pointer += bytesize
    @cursor += width
    @cursor_max += width
  end
  alias_method :ed_digit, :ed_insert
  alias_method :self_insert, :ed_insert

  private def ed_quoted_insert(str, arg: 1)
    @waiting_proc = proc { |key|
      arg.times do
        if key == "\C-j".ord or key == "\C-m".ord
          key_newline(key)
        else
          ed_insert(key)
        end
      end
      @waiting_proc = nil
    }
  end
  alias_method :quoted_insert, :ed_quoted_insert

  private def ed_next_char(key, arg: 1)
    byte_size = Reline::Unicode.get_next_mbchar_size(@line, @byte_pointer)
    if (@byte_pointer < @line.bytesize)
      mbchar = @line.byteslice(@byte_pointer, byte_size)
      width = Reline::Unicode.get_mbchar_width(mbchar)
      @cursor += width if width
      @byte_pointer += byte_size
    elsif @is_multiline and @config.editing_mode_is?(:emacs) and @byte_pointer == @line.bytesize and @line_index < @buffer_of_lines.size - 1
      next_line = @buffer_of_lines[@line_index + 1]
      @cursor = 0
      @byte_pointer = 0
      @cursor_max = calculate_width(next_line)
      @previous_line_index = @line_index
      @line_index += 1
    end
    arg -= 1
    ed_next_char(key, arg: arg) if arg > 0
  end
  alias_method :forward_char, :ed_next_char

  private def ed_prev_char(key, arg: 1)
    if @cursor > 0
      byte_size = Reline::Unicode.get_prev_mbchar_size(@line, @byte_pointer)
      @byte_pointer -= byte_size
      mbchar = @line.byteslice(@byte_pointer, byte_size)
      width = Reline::Unicode.get_mbchar_width(mbchar)
      @cursor -= width
    elsif @is_multiline and @config.editing_mode_is?(:emacs) and @byte_pointer == 0 and @line_index > 0
      prev_line = @buffer_of_lines[@line_index - 1]
      @cursor = calculate_width(prev_line)
      @byte_pointer = prev_line.bytesize
      @cursor_max = calculate_width(prev_line)
      @previous_line_index = @line_index
      @line_index -= 1
    end
    arg -= 1
    ed_prev_char(key, arg: arg) if arg > 0
  end
  alias_method :backward_char, :ed_prev_char

  private def vi_first_print(key)
    @byte_pointer, @cursor = Reline::Unicode.vi_first_print(@line)
  end

  private def ed_move_to_beg(key)
    @byte_pointer = @cursor = 0
  end
  alias_method :beginning_of_line, :ed_move_to_beg

  private def ed_move_to_end(key)
    @byte_pointer = 0
    @cursor = 0
    byte_size = 0
    while @byte_pointer < @line.bytesize
      byte_size = Reline::Unicode.get_next_mbchar_size(@line, @byte_pointer)
      if byte_size > 0
        mbchar = @line.byteslice(@byte_pointer, byte_size)
        @cursor += Reline::Unicode.get_mbchar_width(mbchar)
      end
      @byte_pointer += byte_size
    end
  end
  alias_method :end_of_line, :ed_move_to_end

  private def generate_searcher
    Fiber.new do |first_key|
      prev_search_key = first_key
      search_word = String.new(encoding: @encoding)
      multibyte_buf = String.new(encoding: 'ASCII-8BIT')
      last_hit = nil
      case first_key
      when "\C-r".ord
        prompt_name = 'reverse-i-search'
      when "\C-s".ord
        prompt_name = 'i-search'
      end
      loop do
        key = Fiber.yield(search_word)
        search_again = false
        case key
        when -1 # determined
          Reline.last_incremental_search = search_word
          break
        when "\C-h".ord, "\C-?".ord
          grapheme_clusters = search_word.grapheme_clusters
          if grapheme_clusters.size > 0
            grapheme_clusters.pop
            search_word = grapheme_clusters.join
          end
        when "\C-r".ord, "\C-s".ord
          search_again = true if prev_search_key == key
          prev_search_key = key
        else
          multibyte_buf << key
          if multibyte_buf.dup.force_encoding(@encoding).valid_encoding?
            search_word << multibyte_buf.dup.force_encoding(@encoding)
            multibyte_buf.clear
          end
        end
        hit = nil
        if not search_word.empty? and @line_backup_in_history&.include?(search_word)
          @history_pointer = nil
          hit = @line_backup_in_history
        else
          if search_again
            if search_word.empty? and Reline.last_incremental_search
              search_word = Reline.last_incremental_search
            end
            if @history_pointer
              case prev_search_key
              when "\C-r".ord
                history_pointer_base = 0
                history = Reline::HISTORY[0..(@history_pointer - 1)]
              when "\C-s".ord
                history_pointer_base = @history_pointer + 1
                history = Reline::HISTORY[(@history_pointer + 1)..-1]
              end
            else
              history_pointer_base = 0
              history = Reline::HISTORY
            end
          elsif @history_pointer
            case prev_search_key
            when "\C-r".ord
              history_pointer_base = 0
              history = Reline::HISTORY[0..@history_pointer]
            when "\C-s".ord
              history_pointer_base = @history_pointer
              history = Reline::HISTORY[@history_pointer..-1]
            end
          else
            history_pointer_base = 0
            history = Reline::HISTORY
          end
          case prev_search_key
          when "\C-r".ord
            hit_index = history.rindex { |item|
              item.include?(search_word)
            }
          when "\C-s".ord
            hit_index = history.index { |item|
              item.include?(search_word)
            }
          end
          if hit_index
            @history_pointer = history_pointer_base + hit_index
            hit = Reline::HISTORY[@history_pointer]
          end
        end
        case prev_search_key
        when "\C-r".ord
          prompt_name = 'reverse-i-search'
        when "\C-s".ord
          prompt_name = 'i-search'
        end
        if hit
          if @is_multiline
            @buffer_of_lines = hit.split("\n")
            @buffer_of_lines = [String.new(encoding: @encoding)] if @buffer_of_lines.empty?
            @line_index = @buffer_of_lines.size - 1
            @line = @buffer_of_lines.last
            @rerender_all = true
            @searching_prompt = "(%s)`%s'" % [prompt_name, search_word]
          else
            @line = hit
            @searching_prompt = "(%s)`%s': %s" % [prompt_name, search_word, hit]
          end
          last_hit = hit
        else
          if @is_multiline
            @rerender_all = true
            @searching_prompt = "(failed %s)`%s'" % [prompt_name, search_word]
          else
            @searching_prompt = "(failed %s)`%s': %s" % [prompt_name, search_word, last_hit]
          end
        end
      end
    end
  end

  private def incremental_search_history(key)
    unless @history_pointer
      if @is_multiline
        @line_backup_in_history = whole_buffer
      else
        @line_backup_in_history = @line
      end
    end
    searcher = generate_searcher
    searcher.resume(key)
    @searching_prompt = "(reverse-i-search)`': "
    @waiting_proc = ->(k) {
      case k
      when "\C-j".ord
        if @history_pointer
          buffer = Reline::HISTORY[@history_pointer]
        else
          buffer = @line_backup_in_history
        end
        if @is_multiline
          @buffer_of_lines = buffer.split("\n")
          @buffer_of_lines = [String.new(encoding: @encoding)] if @buffer_of_lines.empty?
          @line_index = @buffer_of_lines.size - 1
          @line = @buffer_of_lines.last
          @rerender_all = true
        else
          @line = buffer
        end
        @searching_prompt = nil
        @waiting_proc = nil
        @cursor_max = calculate_width(@line)
        @cursor = @byte_pointer = 0
        searcher.resume(-1)
      when "\C-g".ord
        if @is_multiline
          @buffer_of_lines = @line_backup_in_history.split("\n")
          @buffer_of_lines = [String.new(encoding: @encoding)] if @buffer_of_lines.empty?
          @line_index = @buffer_of_lines.size - 1
          @line = @buffer_of_lines.last
          @rerender_all = true
        else
          @line = @line_backup_in_history
        end
        @history_pointer = nil
        @searching_prompt = nil
        @waiting_proc = nil
        @line_backup_in_history = nil
        @cursor_max = calculate_width(@line)
        @cursor = @byte_pointer = 0
        @rerender_all = true
      else
        chr = k.is_a?(String) ? k : k.chr(Encoding::ASCII_8BIT)
        if chr.match?(/[[:print:]]/) or k == "\C-h".ord or k == "\C-?".ord or k == "\C-r".ord or k == "\C-s".ord
          searcher.resume(k)
        else
          if @history_pointer
            line = Reline::HISTORY[@history_pointer]
          else
            line = @line_backup_in_history
          end
          if @is_multiline
            @line_backup_in_history = whole_buffer
            @buffer_of_lines = line.split("\n")
            @buffer_of_lines = [String.new(encoding: @encoding)] if @buffer_of_lines.empty?
            @line_index = @buffer_of_lines.size - 1
            @line = @buffer_of_lines.last
            @rerender_all = true
          else
            @line_backup_in_history = @line
            @line = line
          end
          @searching_prompt = nil
          @waiting_proc = nil
          @cursor_max = calculate_width(@line)
          @cursor = @byte_pointer = 0
          searcher.resume(-1)
        end
      end
    }
  end

  private def vi_search_prev(key)
    incremental_search_history(key)
  end
  alias_method :reverse_search_history, :vi_search_prev

  private def vi_search_next(key)
    incremental_search_history(key)
  end
  alias_method :forward_search_history, :vi_search_next

  private def ed_search_prev_history(key, arg: 1)
    history = nil
    h_pointer = nil
    line_no = nil
    substr = @line.slice(0, @byte_pointer)
    if @history_pointer.nil?
      return if not @line.empty? and substr.empty?
      history = Reline::HISTORY
    elsif @history_pointer.zero?
      history = nil
      h_pointer = nil
    else
      history = Reline::HISTORY.slice(0, @history_pointer)
    end
    return if history.nil?
    if @is_multiline
      h_pointer = history.rindex { |h|
        h.split("\n").each_with_index { |l, i|
          if l.start_with?(substr)
            line_no = i
            break
          end
        }
        not line_no.nil?
      }
    else
      h_pointer = history.rindex { |l|
        l.start_with?(substr)
      }
    end
    return if h_pointer.nil?
    @history_pointer = h_pointer
    if @is_multiline
      @buffer_of_lines = Reline::HISTORY[@history_pointer].split("\n")
      @buffer_of_lines = [String.new(encoding: @encoding)] if @buffer_of_lines.empty?
      @line_index = line_no
      @line = @buffer_of_lines.last
      @rerender_all = true
    else
      @line = Reline::HISTORY[@history_pointer]
    end
    @cursor_max = calculate_width(@line)
    arg -= 1
    ed_search_prev_history(key, arg: arg) if arg > 0
  end
  alias_method :history_search_backward, :ed_search_prev_history

  private def ed_search_next_history(key, arg: 1)
    substr = @line.slice(0, @byte_pointer)
    if @history_pointer.nil?
      return
    elsif @history_pointer == (Reline::HISTORY.size - 1) and not substr.empty?
      return
    end
    history = Reline::HISTORY.slice((@history_pointer + 1)..-1)
    h_pointer = nil
    line_no = nil
    if @is_multiline
      h_pointer = history.index { |h|
        h.split("\n").each_with_index { |l, i|
          if l.start_with?(substr)
            line_no = i
            break
          end
        }
        not line_no.nil?
      }
    else
      h_pointer = history.index { |l|
        l.start_with?(substr)
      }
    end
    h_pointer += @history_pointer + 1 if h_pointer and @history_pointer
    return if h_pointer.nil? and not substr.empty?
    @history_pointer = h_pointer
    if @is_multiline
      if @history_pointer.nil? and substr.empty?
        @buffer_of_lines = []
        @line_index = 0
      else
        @buffer_of_lines = Reline::HISTORY[@history_pointer].split("\n")
        @line_index = line_no
      end
      @buffer_of_lines = [String.new(encoding: @encoding)] if @buffer_of_lines.empty?
      @line = @buffer_of_lines.last
      @rerender_all = true
    else
      if @history_pointer.nil? and substr.empty?
        @line = ''
      else
        @line = Reline::HISTORY[@history_pointer]
      end
    end
    @cursor_max = calculate_width(@line)
    arg -= 1
    ed_search_next_history(key, arg: arg) if arg > 0
  end
  alias_method :history_search_forward, :ed_search_next_history

  private def ed_prev_history(key, arg: 1)
    if @is_multiline and @line_index > 0
      @previous_line_index = @line_index
      @line_index -= 1
      return
    end
    if Reline::HISTORY.empty?
      return
    end
    if @history_pointer.nil?
      @history_pointer = Reline::HISTORY.size - 1
      if @is_multiline
        @line_backup_in_history = whole_buffer
        @buffer_of_lines = Reline::HISTORY[@history_pointer].split("\n")
        @buffer_of_lines = [String.new(encoding: @encoding)] if @buffer_of_lines.empty?
        @line_index = @buffer_of_lines.size - 1
        @line = @buffer_of_lines.last
        @rerender_all = true
      else
        @line_backup_in_history = @line
        @line = Reline::HISTORY[@history_pointer]
      end
    elsif @history_pointer.zero?
      return
    else
      if @is_multiline
        Reline::HISTORY[@history_pointer] = whole_buffer
        @history_pointer -= 1
        @buffer_of_lines = Reline::HISTORY[@history_pointer].split("\n")
        @buffer_of_lines = [String.new(encoding: @encoding)] if @buffer_of_lines.empty?
        @line_index = @buffer_of_lines.size - 1
        @line = @buffer_of_lines.last
        @rerender_all = true
      else
        Reline::HISTORY[@history_pointer] = @line
        @history_pointer -= 1
        @line = Reline::HISTORY[@history_pointer]
      end
    end
    if @config.editing_mode_is?(:emacs, :vi_insert)
      @cursor_max = @cursor = calculate_width(@line)
      @byte_pointer = @line.bytesize
    elsif @config.editing_mode_is?(:vi_command)
      @byte_pointer = @cursor = 0
      @cursor_max = calculate_width(@line)
    end
    arg -= 1
    ed_prev_history(key, arg: arg) if arg > 0
  end

  private def ed_next_history(key, arg: 1)
    if @is_multiline and @line_index < (@buffer_of_lines.size - 1)
      @previous_line_index = @line_index
      @line_index += 1
      return
    end
    if @history_pointer.nil?
      return
    elsif @history_pointer == (Reline::HISTORY.size - 1)
      if @is_multiline
        @history_pointer = nil
        @buffer_of_lines = @line_backup_in_history.split("\n")
        @buffer_of_lines = [String.new(encoding: @encoding)] if @buffer_of_lines.empty?
        @line_index = 0
        @line = @buffer_of_lines.first
        @rerender_all = true
      else
        @history_pointer = nil
        @line = @line_backup_in_history
      end
    else
      if @is_multiline
        Reline::HISTORY[@history_pointer] = whole_buffer
        @history_pointer += 1
        @buffer_of_lines = Reline::HISTORY[@history_pointer].split("\n")
        @buffer_of_lines = [String.new(encoding: @encoding)] if @buffer_of_lines.empty?
        @line_index = 0
        @line = @buffer_of_lines.first
        @rerender_all = true
      else
        Reline::HISTORY[@history_pointer] = @line
        @history_pointer += 1
        @line = Reline::HISTORY[@history_pointer]
      end
    end
    @line = '' unless @line
    if @config.editing_mode_is?(:emacs, :vi_insert)
      @cursor_max = @cursor = calculate_width(@line)
      @byte_pointer = @line.bytesize
    elsif @config.editing_mode_is?(:vi_command)
      @byte_pointer = @cursor = 0
      @cursor_max = calculate_width(@line)
    end
    arg -= 1
    ed_next_history(key, arg: arg) if arg > 0
  end

  private def ed_newline(key)
    process_insert(force: true)
    if @is_multiline
      if @config.editing_mode_is?(:vi_command)
        if @line_index < (@buffer_of_lines.size - 1)
          ed_next_history(key) # means cursor down
        else
          # should check confirm_multiline_termination to finish?
          finish
        end
      else
        if @line_index == (@buffer_of_lines.size - 1)
          if confirm_multiline_termination
            finish
          else
            key_newline(key)
          end
        else
          # should check confirm_multiline_termination to finish?
          @previous_line_index = @line_index
          @line_index = @buffer_of_lines.size - 1
          finish
        end
      end
    else
      if @history_pointer
        Reline::HISTORY[@history_pointer] = @line
        @history_pointer = nil
      end
      finish
    end
  end

  private def em_delete_prev_char(key)
    if @is_multiline and @cursor == 0 and @line_index > 0
      @buffer_of_lines[@line_index] = @line
      @cursor = calculate_width(@buffer_of_lines[@line_index - 1])
      @byte_pointer = @buffer_of_lines[@line_index - 1].bytesize
      @buffer_of_lines[@line_index - 1] += @buffer_of_lines.delete_at(@line_index)
      @line_index -= 1
      @line = @buffer_of_lines[@line_index]
      @cursor_max = calculate_width(@line)
      @rerender_all = true
    elsif @cursor > 0
      byte_size = Reline::Unicode.get_prev_mbchar_size(@line, @byte_pointer)
      @byte_pointer -= byte_size
      @line, mbchar = byteslice!(@line, @byte_pointer, byte_size)
      width = Reline::Unicode.get_mbchar_width(mbchar)
      @cursor -= width
      @cursor_max -= width
    end
  end
  alias_method :backward_delete_char, :em_delete_prev_char

  private def ed_kill_line(key)
    if @line.bytesize > @byte_pointer
      @line, deleted = byteslice!(@line, @byte_pointer, @line.bytesize - @byte_pointer)
      @byte_pointer = @line.bytesize
      @cursor = @cursor_max = calculate_width(@line)
      @kill_ring.append(deleted)
    elsif @is_multiline and @byte_pointer == @line.bytesize and @buffer_of_lines.size > @line_index + 1
      @cursor = calculate_width(@line)
      @byte_pointer = @line.bytesize
      @line += @buffer_of_lines.delete_at(@line_index + 1)
      @cursor_max = calculate_width(@line)
      @buffer_of_lines[@line_index] = @line
      @rerender_all = true
      @rest_height += 1
    end
  end

  private def em_kill_line(key)
    if @byte_pointer > 0
      @line, deleted = byteslice!(@line, 0, @byte_pointer)
      @byte_pointer = 0
      @kill_ring.append(deleted, true)
      @cursor_max = calculate_width(@line)
      @cursor = 0
    end
  end

  private def em_delete(key)
    if (not @is_multiline and @line.empty?) or (@is_multiline and @line.empty? and @buffer_of_lines.size == 1)
      @line = nil
      if @buffer_of_lines.size > 1
        scroll_down(@highest_in_all - @first_line_started_from)
      end
      Reline::IOGate.move_cursor_column(0)
      @eof = true
      finish
    elsif @byte_pointer < @line.bytesize
      splitted_last = @line.byteslice(@byte_pointer, @line.bytesize)
      mbchar = splitted_last.grapheme_clusters.first
      width = Reline::Unicode.get_mbchar_width(mbchar)
      @cursor_max -= width
      @line, = byteslice!(@line, @byte_pointer, mbchar.bytesize)
    elsif @is_multiline and @byte_pointer == @line.bytesize and @buffer_of_lines.size > @line_index + 1
      @cursor = calculate_width(@line)
      @byte_pointer = @line.bytesize
      @line += @buffer_of_lines.delete_at(@line_index + 1)
      @cursor_max = calculate_width(@line)
      @buffer_of_lines[@line_index] = @line
      @rerender_all = true
      @rest_height += 1
    end
  end
  alias_method :delete_char, :em_delete

  private def em_delete_or_list(key)
    if @line.empty? or @byte_pointer < @line.bytesize
      em_delete(key)
    else # show completed list
      result = call_completion_proc
      if result.is_a?(Array)
        complete(result, true)
      end
    end
  end
  alias_method :delete_char_or_list, :em_delete_or_list

  private def em_yank(key)
    yanked = @kill_ring.yank
    if yanked
      @line = byteinsert(@line, @byte_pointer, yanked)
      yanked_width = calculate_width(yanked)
      @cursor += yanked_width
      @cursor_max += yanked_width
      @byte_pointer += yanked.bytesize
    end
  end

  private def em_yank_pop(key)
    yanked, prev_yank = @kill_ring.yank_pop
    if yanked
      prev_yank_width = calculate_width(prev_yank)
      @cursor -= prev_yank_width
      @cursor_max -= prev_yank_width
      @byte_pointer -= prev_yank.bytesize
      @line, = byteslice!(@line, @byte_pointer, prev_yank.bytesize)
      @line = byteinsert(@line, @byte_pointer, yanked)
      yanked_width = calculate_width(yanked)
      @cursor += yanked_width
      @cursor_max += yanked_width
      @byte_pointer += yanked.bytesize
    end
  end

  private def ed_clear_screen(key)
    @cleared = true
  end
  alias_method :clear_screen, :ed_clear_screen

  private def em_next_word(key)
    if @line.bytesize > @byte_pointer
      byte_size, width = Reline::Unicode.em_forward_word(@line, @byte_pointer)
      @byte_pointer += byte_size
      @cursor += width
    end
  end
  alias_method :forward_word, :em_next_word

  private def ed_prev_word(key)
    if @byte_pointer > 0
      byte_size, width = Reline::Unicode.em_backward_word(@line, @byte_pointer)
      @byte_pointer -= byte_size
      @cursor -= width
    end
  end
  alias_method :backward_word, :ed_prev_word

  private def em_delete_next_word(key)
    if @line.bytesize > @byte_pointer
      byte_size, width = Reline::Unicode.em_forward_word(@line, @byte_pointer)
      @line, word = byteslice!(@line, @byte_pointer, byte_size)
      @kill_ring.append(word)
      @cursor_max -= width
    end
  end

  private def ed_delete_prev_word(key)
    if @byte_pointer > 0
      byte_size, width = Reline::Unicode.em_backward_word(@line, @byte_pointer)
      @line, word = byteslice!(@line, @byte_pointer - byte_size, byte_size)
      @kill_ring.append(word, true)
      @byte_pointer -= byte_size
      @cursor -= width
      @cursor_max -= width
    end
  end

  private def ed_transpose_chars(key)
    if @byte_pointer > 0
      if @cursor_max > @cursor
        byte_size = Reline::Unicode.get_next_mbchar_size(@line, @byte_pointer)
        mbchar = @line.byteslice(@byte_pointer, byte_size)
        width = Reline::Unicode.get_mbchar_width(mbchar)
        @cursor += width
        @byte_pointer += byte_size
      end
      back1_byte_size = Reline::Unicode.get_prev_mbchar_size(@line, @byte_pointer)
      if (@byte_pointer - back1_byte_size) > 0
        back2_byte_size = Reline::Unicode.get_prev_mbchar_size(@line, @byte_pointer - back1_byte_size)
        back2_pointer = @byte_pointer - back1_byte_size - back2_byte_size
        @line, back2_mbchar = byteslice!(@line, back2_pointer, back2_byte_size)
        @line = byteinsert(@line, @byte_pointer - back2_byte_size, back2_mbchar)
      end
    end
  end
  alias_method :transpose_chars, :ed_transpose_chars

  private def ed_transpose_words(key)
    left_word_start, middle_start, right_word_start, after_start = Reline::Unicode.ed_transpose_words(@line, @byte_pointer)
    before = @line.byteslice(0, left_word_start)
    left_word = @line.byteslice(left_word_start, middle_start - left_word_start)
    middle = @line.byteslice(middle_start, right_word_start - middle_start)
    right_word = @line.byteslice(right_word_start, after_start - right_word_start)
    after = @line.byteslice(after_start, @line.bytesize - after_start)
    return if left_word.empty? or right_word.empty?
    @line = before + right_word + middle + left_word + after
    from_head_to_left_word = before + right_word + middle + left_word
    @byte_pointer = from_head_to_left_word.bytesize
    @cursor = calculate_width(from_head_to_left_word)
  end
  alias_method :transpose_words, :ed_transpose_words

  private def em_capitol_case(key)
    if @line.bytesize > @byte_pointer
      byte_size, _, new_str = Reline::Unicode.em_forward_word_with_capitalization(@line, @byte_pointer)
      before = @line.byteslice(0, @byte_pointer)
      after = @line.byteslice((@byte_pointer + byte_size)..-1)
      @line = before + new_str + after
      @byte_pointer += new_str.bytesize
      @cursor += calculate_width(new_str)
    end
  end
  alias_method :capitalize_word, :em_capitol_case

  private def em_lower_case(key)
    if @line.bytesize > @byte_pointer
      byte_size, = Reline::Unicode.em_forward_word(@line, @byte_pointer)
      part = @line.byteslice(@byte_pointer, byte_size).grapheme_clusters.map { |mbchar|
        mbchar =~ /[A-Z]/ ? mbchar.downcase : mbchar
      }.join
      rest = @line.byteslice((@byte_pointer + byte_size)..-1)
      @line = @line.byteslice(0, @byte_pointer) + part
      @byte_pointer = @line.bytesize
      @cursor = calculate_width(@line)
      @cursor_max = @cursor + calculate_width(rest)
      @line += rest
    end
  end
  alias_method :downcase_word, :em_lower_case

  private def em_upper_case(key)
    if @line.bytesize > @byte_pointer
      byte_size, = Reline::Unicode.em_forward_word(@line, @byte_pointer)
      part = @line.byteslice(@byte_pointer, byte_size).grapheme_clusters.map { |mbchar|
        mbchar =~ /[a-z]/ ? mbchar.upcase : mbchar
      }.join
      rest = @line.byteslice((@byte_pointer + byte_size)..-1)
      @line = @line.byteslice(0, @byte_pointer) + part
      @byte_pointer = @line.bytesize
      @cursor = calculate_width(@line)
      @cursor_max = @cursor + calculate_width(rest)
      @line += rest
    end
  end
  alias_method :upcase_word, :em_upper_case

  private def em_kill_region(key)
    if @byte_pointer > 0
      byte_size, width = Reline::Unicode.em_big_backward_word(@line, @byte_pointer)
      @line, deleted = byteslice!(@line, @byte_pointer - byte_size, byte_size)
      @byte_pointer -= byte_size
      @cursor -= width
      @cursor_max -= width
      @kill_ring.append(deleted)
    end
  end

  private def copy_for_vi(text)
    if @config.editing_mode_is?(:vi_insert) or @config.editing_mode_is?(:vi_command)
      @vi_clipboard = text
    end
  end

  private def vi_insert(key)
    @config.editing_mode = :vi_insert
  end

  private def vi_add(key)
    @config.editing_mode = :vi_insert
    ed_next_char(key)
  end

  private def vi_command_mode(key)
    ed_prev_char(key)
    @config.editing_mode = :vi_command
  end
  alias_method :vi_movement_mode, :vi_command_mode

  private def vi_next_word(key, arg: 1)
    if @line.bytesize > @byte_pointer
      byte_size, width = Reline::Unicode.vi_forward_word(@line, @byte_pointer)
      @byte_pointer += byte_size
      @cursor += width
    end
    arg -= 1
    vi_next_word(key, arg: arg) if arg > 0
  end

  private def vi_prev_word(key, arg: 1)
    if @byte_pointer > 0
      byte_size, width = Reline::Unicode.vi_backward_word(@line, @byte_pointer)
      @byte_pointer -= byte_size
      @cursor -= width
    end
    arg -= 1
    vi_prev_word(key, arg: arg) if arg > 0
  end

  private def vi_end_word(key, arg: 1, inclusive: false)
    if @line.bytesize > @byte_pointer
      byte_size, width = Reline::Unicode.vi_forward_end_word(@line, @byte_pointer)
      @byte_pointer += byte_size
      @cursor += width
    end
    arg -= 1
    if inclusive and arg.zero?
      byte_size = Reline::Unicode.get_next_mbchar_size(@line, @byte_pointer)
      if byte_size > 0
        c = @line.byteslice(@byte_pointer, byte_size)
        width = Reline::Unicode.get_mbchar_width(c)
        @byte_pointer += byte_size
        @cursor += width
      end
    end
    vi_end_word(key, arg: arg) if arg > 0
  end

  private def vi_next_big_word(key, arg: 1)
    if @line.bytesize > @byte_pointer
      byte_size, width = Reline::Unicode.vi_big_forward_word(@line, @byte_pointer)
      @byte_pointer += byte_size
      @cursor += width
    end
    arg -= 1
    vi_next_big_word(key, arg: arg) if arg > 0
  end

  private def vi_prev_big_word(key, arg: 1)
    if @byte_pointer > 0
      byte_size, width = Reline::Unicode.vi_big_backward_word(@line, @byte_pointer)
      @byte_pointer -= byte_size
      @cursor -= width
    end
    arg -= 1
    vi_prev_big_word(key, arg: arg) if arg > 0
  end

  private def vi_end_big_word(key, arg: 1, inclusive: false)
    if @line.bytesize > @byte_pointer
      byte_size, width = Reline::Unicode.vi_big_forward_end_word(@line, @byte_pointer)
      @byte_pointer += byte_size
      @cursor += width
    end
    arg -= 1
    if inclusive and arg.zero?
      byte_size = Reline::Unicode.get_next_mbchar_size(@line, @byte_pointer)
      if byte_size > 0
        c = @line.byteslice(@byte_pointer, byte_size)
        width = Reline::Unicode.get_mbchar_width(c)
        @byte_pointer += byte_size
        @cursor += width
      end
    end
    vi_end_big_word(key, arg: arg) if arg > 0
  end

  private def vi_delete_prev_char(key)
    if @is_multiline and @cursor == 0 and @line_index > 0
      @buffer_of_lines[@line_index] = @line
      @cursor = calculate_width(@buffer_of_lines[@line_index - 1])
      @byte_pointer = @buffer_of_lines[@line_index - 1].bytesize
      @buffer_of_lines[@line_index - 1] += @buffer_of_lines.delete_at(@line_index)
      @line_index -= 1
      @line = @buffer_of_lines[@line_index]
      @cursor_max = calculate_width(@line)
      @rerender_all = true
    elsif @cursor > 0
      byte_size = Reline::Unicode.get_prev_mbchar_size(@line, @byte_pointer)
      @byte_pointer -= byte_size
      @line, mbchar = byteslice!(@line, @byte_pointer, byte_size)
      width = Reline::Unicode.get_mbchar_width(mbchar)
      @cursor -= width
      @cursor_max -= width
    end
  end

  private def vi_insert_at_bol(key)
    ed_move_to_beg(key)
    @config.editing_mode = :vi_insert
  end

  private def vi_add_at_eol(key)
    ed_move_to_end(key)
    @config.editing_mode = :vi_insert
  end

  private def ed_delete_prev_char(key, arg: 1)
    deleted = ''
    arg.times do
      if @cursor > 0
        byte_size = Reline::Unicode.get_prev_mbchar_size(@line, @byte_pointer)
        @byte_pointer -= byte_size
        @line, mbchar = byteslice!(@line, @byte_pointer, byte_size)
        deleted.prepend(mbchar)
        width = Reline::Unicode.get_mbchar_width(mbchar)
        @cursor -= width
        @cursor_max -= width
      end
    end
    copy_for_vi(deleted)
  end

  private def vi_zero(key)
    @byte_pointer = 0
    @cursor = 0
  end

  private def vi_change_meta(key)
    @waiting_operator_proc = proc { |cursor_diff, byte_pointer_diff|
      if byte_pointer_diff > 0
        @line, cut = byteslice!(@line, @byte_pointer, byte_pointer_diff)
      elsif byte_pointer_diff < 0
        @line, cut = byteslice!(@line, @byte_pointer + byte_pointer_diff, -byte_pointer_diff)
      end
      copy_for_vi(cut)
      @cursor += cursor_diff if cursor_diff < 0
      @cursor_max -= cursor_diff.abs
      @byte_pointer += byte_pointer_diff if byte_pointer_diff < 0
      @config.editing_mode = :vi_insert
    }
  end

  private def vi_delete_meta(key)
    @waiting_operator_proc = proc { |cursor_diff, byte_pointer_diff|
      if byte_pointer_diff > 0
        @line, cut = byteslice!(@line, @byte_pointer, byte_pointer_diff)
      elsif byte_pointer_diff < 0
        @line, cut = byteslice!(@line, @byte_pointer + byte_pointer_diff, -byte_pointer_diff)
      end
      copy_for_vi(cut)
      @cursor += cursor_diff if cursor_diff < 0
      @cursor_max -= cursor_diff.abs
      @byte_pointer += byte_pointer_diff if byte_pointer_diff < 0
    }
  end

  private def vi_yank(key)
    @waiting_operator_proc = proc { |cursor_diff, byte_pointer_diff|
      if byte_pointer_diff > 0
        cut = @line.byteslice(@byte_pointer, byte_pointer_diff)
      elsif byte_pointer_diff < 0
        cut = @line.byteslice(@byte_pointer + byte_pointer_diff, -byte_pointer_diff)
      end
      copy_for_vi(cut)
    }
  end

  private def vi_list_or_eof(key)
    if (not @is_multiline and @line.empty?) or (@is_multiline and @line.empty? and @buffer_of_lines.size == 1)
      @line = nil
      if @buffer_of_lines.size > 1
        scroll_down(@highest_in_all - @first_line_started_from)
      end
      Reline::IOGate.move_cursor_column(0)
      @eof = true
      finish
    else
      ed_newline(key)
    end
  end
  alias_method :vi_end_of_transmission, :vi_list_or_eof
  alias_method :vi_eof_maybe, :vi_list_or_eof

  private def ed_delete_next_char(key, arg: 1)
    byte_size = Reline::Unicode.get_next_mbchar_size(@line, @byte_pointer)
    unless @line.empty? || byte_size == 0
      @line, mbchar = byteslice!(@line, @byte_pointer, byte_size)
      copy_for_vi(mbchar)
      width = Reline::Unicode.get_mbchar_width(mbchar)
      @cursor_max -= width
      if @cursor > 0 and @cursor >= @cursor_max
        @byte_pointer -= byte_size
        @cursor -= width
      end
    end
    arg -= 1
    ed_delete_next_char(key, arg: arg) if arg > 0
  end

  private def vi_to_history_line(key)
    if Reline::HISTORY.empty?
      return
    end
    if @history_pointer.nil?
      @history_pointer = 0
      @line_backup_in_history = @line
      @line = Reline::HISTORY[@history_pointer]
      @cursor_max = calculate_width(@line)
      @cursor = 0
      @byte_pointer = 0
    elsif @history_pointer.zero?
      return
    else
      Reline::HISTORY[@history_pointer] = @line
      @history_pointer = 0
      @line = Reline::HISTORY[@history_pointer]
      @cursor_max = calculate_width(@line)
      @cursor = 0
      @byte_pointer = 0
    end
  end

  private def vi_histedit(key)
    path = Tempfile.open { |fp|
      fp.write @line
      fp.path
    }
    system("#{ENV['EDITOR']} #{path}")
    @line = File.read(path)
    finish
  end

  private def vi_paste_prev(key, arg: 1)
    if @vi_clipboard.size > 0
      @line = byteinsert(@line, @byte_pointer, @vi_clipboard)
      @cursor_max += calculate_width(@vi_clipboard)
      cursor_point = @vi_clipboard.grapheme_clusters[0..-2].join
      @cursor += calculate_width(cursor_point)
      @byte_pointer += cursor_point.bytesize
    end
    arg -= 1
    vi_paste_prev(key, arg: arg) if arg > 0
  end

  private def vi_paste_next(key, arg: 1)
    if @vi_clipboard.size > 0
      byte_size = Reline::Unicode.get_next_mbchar_size(@line, @byte_pointer)
      @line = byteinsert(@line, @byte_pointer + byte_size, @vi_clipboard)
      @cursor_max += calculate_width(@vi_clipboard)
      @cursor += calculate_width(@vi_clipboard)
      @byte_pointer += @vi_clipboard.bytesize
    end
    arg -= 1
    vi_paste_next(key, arg: arg) if arg > 0
  end

  private def ed_argument_digit(key)
    if @vi_arg.nil?
      unless key.chr.to_i.zero?
        @vi_arg = key.chr.to_i
      end
    else
      @vi_arg = @vi_arg * 10 + key.chr.to_i
    end
  end

  private def vi_to_column(key, arg: 0)
    @byte_pointer, @cursor = @line.grapheme_clusters.inject([0, 0]) { |total, gc|
      # total has [byte_size, cursor]
      mbchar_width = Reline::Unicode.get_mbchar_width(gc)
      if (total.last + mbchar_width) >= arg
        break total
      elsif (total.last + mbchar_width) >= @cursor_max
        break total
      else
        total = [total.first + gc.bytesize, total.last + mbchar_width]
        total
      end
    }
  end

  private def vi_replace_char(key, arg: 1)
    @waiting_proc = ->(k) {
      if arg == 1
        byte_size = Reline::Unicode.get_next_mbchar_size(@line, @byte_pointer)
        before = @line.byteslice(0, @byte_pointer)
        remaining_point = @byte_pointer + byte_size
        after = @line.byteslice(remaining_point, @line.size - remaining_point)
        @line = before + k.chr + after
        @cursor_max = calculate_width(@line)
        @waiting_proc = nil
      elsif arg > 1
        byte_size = 0
        arg.times do
          byte_size += Reline::Unicode.get_next_mbchar_size(@line, @byte_pointer + byte_size)
        end
        before = @line.byteslice(0, @byte_pointer)
        remaining_point = @byte_pointer + byte_size
        after = @line.byteslice(remaining_point, @line.size - remaining_point)
        replaced = k.chr * arg
        @line = before + replaced + after
        @byte_pointer += replaced.bytesize
        @cursor += calculate_width(replaced)
        @cursor_max = calculate_width(@line)
        @waiting_proc = nil
      end
    }
  end

  private def vi_next_char(key, arg: 1, inclusive: false)
    @waiting_proc = ->(key_for_proc) { search_next_char(key_for_proc, arg, inclusive: inclusive) }
  end

  private def vi_to_next_char(key, arg: 1, inclusive: false)
    @waiting_proc = ->(key_for_proc) { search_next_char(key_for_proc, arg, need_prev_char: true, inclusive: inclusive) }
  end

  private def search_next_char(key, arg, need_prev_char: false, inclusive: false)
    if key.instance_of?(String)
      inputed_char = key
    else
      inputed_char = key.chr
    end
    prev_total = nil
    total = nil
    found = false
    @line.byteslice(@byte_pointer..-1).grapheme_clusters.each do |mbchar|
      # total has [byte_size, cursor]
      unless total
        # skip cursor point
        width = Reline::Unicode.get_mbchar_width(mbchar)
        total = [mbchar.bytesize, width]
      else
        if inputed_char == mbchar
          arg -= 1
          if arg.zero?
            found = true
            break
          end
        end
        width = Reline::Unicode.get_mbchar_width(mbchar)
        prev_total = total
        total = [total.first + mbchar.bytesize, total.last + width]
      end
    end
    if not need_prev_char and found and total
      byte_size, width = total
      @byte_pointer += byte_size
      @cursor += width
    elsif need_prev_char and found and prev_total
      byte_size, width = prev_total
      @byte_pointer += byte_size
      @cursor += width
    end
    if inclusive
      byte_size = Reline::Unicode.get_next_mbchar_size(@line, @byte_pointer)
      if byte_size > 0
        c = @line.byteslice(@byte_pointer, byte_size)
        width = Reline::Unicode.get_mbchar_width(c)
        @byte_pointer += byte_size
        @cursor += width
      end
    end
    @waiting_proc = nil
  end

  private def vi_prev_char(key, arg: 1)
    @waiting_proc = ->(key_for_proc) { search_prev_char(key_for_proc, arg) }
  end

  private def vi_to_prev_char(key, arg: 1)
    @waiting_proc = ->(key_for_proc) { search_prev_char(key_for_proc, arg, true) }
  end

  private def search_prev_char(key, arg, need_next_char = false)
    if key.instance_of?(String)
      inputed_char = key
    else
      inputed_char = key.chr
    end
    prev_total = nil
    total = nil
    found = false
    @line.byteslice(0..@byte_pointer).grapheme_clusters.reverse_each do |mbchar|
      # total has [byte_size, cursor]
      unless total
        # skip cursor point
        width = Reline::Unicode.get_mbchar_width(mbchar)
        total = [mbchar.bytesize, width]
      else
        if inputed_char == mbchar
          arg -= 1
          if arg.zero?
            found = true
            break
          end
        end
        width = Reline::Unicode.get_mbchar_width(mbchar)
        prev_total = total
        total = [total.first + mbchar.bytesize, total.last + width]
      end
    end
    if not need_next_char and found and total
      byte_size, width = total
      @byte_pointer -= byte_size
      @cursor -= width
    elsif need_next_char and found and prev_total
      byte_size, width = prev_total
      @byte_pointer -= byte_size
      @cursor -= width
    end
    @waiting_proc = nil
  end

  private def vi_join_lines(key, arg: 1)
    if @is_multiline and @buffer_of_lines.size > @line_index + 1
      @cursor = calculate_width(@line)
      @byte_pointer = @line.bytesize
      @line += ' ' + @buffer_of_lines.delete_at(@line_index + 1).lstrip
      @cursor_max = calculate_width(@line)
      @buffer_of_lines[@line_index] = @line
      @rerender_all = true
      @rest_height += 1
    end
    arg -= 1
    vi_join_lines(key, arg: arg) if arg > 0
  end

  private def em_set_mark(key)
    @mark_pointer = [@byte_pointer, @line_index]
  end
  alias_method :set_mark, :em_set_mark

  private def em_exchange_mark(key)
    return unless @mark_pointer
    new_pointer = [@byte_pointer, @line_index]
    @previous_line_index = @line_index
    @byte_pointer, @line_index = @mark_pointer
    @cursor = calculate_width(@line.byteslice(0, @byte_pointer))
    @cursor_max = calculate_width(@line)
    @mark_pointer = new_pointer
  end
  alias_method :exchange_point_and_mark, :em_exchange_mark
end
