#
# Canvas Text widget demo (called by 'widget')
#

# toplevel widget が存在すれば削除する
if defined?($ctext_demo) && $ctext_demo
  $ctext_demo.destroy 
  $ctext_demo = nil
end

# demo 用の toplevel widget を生成
$ctext_demo = TkToplevel.new {|w|
  title("Canvas Text Demonstration")
  iconname("Text")
  positionWindow(w)
}

# label 生成
TkLabel.new($ctext_demo, 'font'=>$font, 'wraplength'=>'5i', 'justify'=>'left', 
            'text'=>"このウィンドウにはキャンバスwidgetのテキスト機能をデモするためのテキスト文字列が表示されています。マウスを四角の中に持っていき、クリックすると位置ぎめ用の点からの相対位置を変えたり、行揃えを変えたりすることができます。また以下のような編集のための簡単なバインディングをサポートしています。

  1. マウスを持っていき、クリックし、入力できます。
  2. ボタン1で選択できます。
  3. マウスの位置にボタン2で選択したテキストをコピーできます。
  4.バックスペースをコントロール-Hで挿入カーソルの直前の文字を削除します。
  5. Deleteキーは挿入カーソルの直後の文字を削除します。"){
  pack('side'=>'top')
}

# frame 生成
$ctext_buttons = TkFrame.new($ctext_demo) {|frame|
  TkButton.new(frame) {
    #text '了解'
    text '閉じる'
    command proc{
      tmppath = $ctext_demo
      $ctext_demo = nil
      tmppath.destroy
    }
  }.pack('side'=>'left', 'expand'=>'yes')

  TkButton.new(frame) {
    text 'コード参照'
    command proc{showCode 'ctext'}
  }.pack('side'=>'left', 'expand'=>'yes')
}
$ctext_buttons.pack('side'=>'bottom', 'fill'=>'x', 'pady'=>'2m')

# canvas 生成
$ctext_canvas = TkCanvas.new($ctext_demo, 'relief'=>'flat', 
                             'borderwidth'=>0, 'width'=>500, 'height'=>350)
$ctext_canvas.pack('side'=>'top', 'expand'=>'yes', 'fill'=>'both')

# font 設定
textFont = '-*-Helvetica-Medium-R-Normal--*-240-*-*-*-*-*-*'

# canvas 設定
TkcRectangle.new($ctext_canvas, 245, 195, 255, 205, 
                 'outline'=>'black', 'fill'=>'red')

$ctag_text = TkcTag.new($ctext_canvas)
$ctag_text.withtag(TkcText.new($ctext_canvas, 250, 200, 
                               'text'=>"これはキャンバスwidgetのテキスト機能をデモするための文字列です。マウスを持っていき、クリックして入力できます。選択してコントロール-Dで消去することもできます。",
                               'width'=>440, 'anchor'=>'n', 
                               'font'=>'-*-Helvetica-Medium-R-Normal--*-240-*-*-*-*-*-*', 
                               'kanjifont'=>'-*-r-*--24-*-jisx0208.1983-0', 
                               'justify'=>'left') )

$ctag_text.bind('1', proc{|x,y| textB1Press $ctext_canvas,x,y}, "%x %y")
$ctag_text.bind('B1-Motion', proc{|x,y| textB1Move $ctext_canvas,x,y}, "%x %y")
$ctag_text.bind('Shift-1', 
        proc{|x,y| $ctext_canvas.seleect_adjust 'current', "@#{x},#{y}"}, 
        "%x %y")
$ctag_text.bind('Shift-B1-Motion', 
                proc{|x,y| textB1Move $ctext_canvas,x,y}, "%x %y")
$ctag_text.bind('KeyPress', proc{|a| textInsert $ctext_canvas,a}, "%A")
$ctag_text.bind('Return', proc{textInsert $ctext_canvas,"\n"})
$ctag_text.bind('Control-h', proc{textBs $ctext_canvas})
$ctag_text.bind('BackSpace', proc{textBs $ctext_canvas})
$ctag_text.bind('Delete', proc{textDel $ctext_canvas})
$ctag_text.bind('2', proc{|x,y| textPaste $ctext_canvas, "@#{x},#{y}"}, 
                "%x %y")

# Next, create some items that allow the text's anchor position 
# to be edited.

def mkTextConfig(w,x,y,option,value,color)
  item = TkcRectangle.new(w, x, y, x+30, y+30, 
                          'outline'=>'black', 'fill'=>color, 'width'=>1)
  item.bind('1', proc{$ctag_text.configure option, value})
  w.addtag_withtag('config', item)
end

x = 50
y = 50
color = 'LightSkyBlue1'
mkTextConfig $ctext_canvas, x, y, 'anchor', 'se', color
mkTextConfig $ctext_canvas, x+30, y, 'anchor', 's', color
mkTextConfig $ctext_canvas, x+60, y, 'anchor', 'sw', color
mkTextConfig $ctext_canvas, x, y+30, 'anchor', 'e', color
mkTextConfig $ctext_canvas, x+30, y+30, 'anchor', 'center', color
mkTextConfig $ctext_canvas, x+60, y+30, 'anchor', 'w', color
mkTextConfig $ctext_canvas, x, y+60, 'anchor', 'ne', color
mkTextConfig $ctext_canvas, x+30, y+60, 'anchor', 'n', color
mkTextConfig $ctext_canvas, x+60, y+60, 'anchor', 'nw', color
item = TkcRectangle.new($ctext_canvas, x+40, y+40, x+50, y+50, 
                        'outline'=>'black', 'fill'=>'red')
item.bind('1', proc{$ctag_text.configure 'anchor', 'center'})
TkcText.new($ctext_canvas, x+45, y-5, 'text'=>'Text Position', 'anchor'=>'s', 
            'font'=>'-*-times-medium-r-normal--*-240-*-*-*-*-*-*', 
            'fill'=>'brown')

# Lastly, create some items that allow the text's justification to be
# changed.

x = 350
y = 50
color = 'SeaGreen2'
mkTextConfig $ctext_canvas, x, y, 'justify', 'left', color
mkTextConfig $ctext_canvas, x+30, y, 'justify', 'center', color
mkTextConfig $ctext_canvas, x+60, y, 'justify', 'right', color
TkcText.new($ctext_canvas, x+45, y-5, 'text'=>'Justification', 'anchor'=>'s', 
            'font'=>'-*-times-medium-r-normal--*-240-*-*-*-*-*-*', 
            'fill'=>'brown')

$ctext_canvas.itembind('config', 'Enter', proc{textEnter $ctext_canvas})
$ctext_canvas.itembind('config', 'Leave', 
                       proc{$ctext_canvas\
                             .itemconfigure('current', 
                                            'fill'=>$textConfigFill)})

$textConfigFill = ''

def textEnter(w)
  $textConfigFill = (w.itemconfiginfo 'current', 'fill')[4]
  w.itemconfigure 'current', 'fill', 'black'
end

def textInsert(w, string)
  return if string == ""
  begin
    $ctag_text.dchars 'sel.first', 'sel.last'
  rescue
  end
  $ctag_text.insert 'insert', string
end

def textPaste(w, pos)
  begin
    $ctag_text.insert pos, TkSelection.get
  rescue
  end
end

def textB1Press(w,x,y)
  w.icursor 'current', "@#{x},#{y}"
  w.itemfocus 'current'
  w.focus
  w.select_from 'current', "@#{x},#{y}"
end

def textB1Move(w,x,y)
  w.select_to 'current', "@#{x},#{y}"
end

def textBs(w)
  begin
    $ctag_text.dchars 'sel.first', 'sel.last'
  rescue
    char = $ctag_text.index('insert').to_i - 1
    $ctag_text.dchars(char) if char >= 0
  end
end

def textDel(w)
  begin
    $ctag_text.dchars 'sel.first', 'sel.last'
  rescue
    $ctag_text.dchars 'insert'
  end
end

