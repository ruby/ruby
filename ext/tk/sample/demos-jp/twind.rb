# -*- coding: utf-8 -*-
#
# text (embedded windows) widget demo (called by 'widget')
#

# toplevel widget が存在すれば削除する
if defined?($twind_demo) && $twind_demo
  $twind_demo.destroy
  $twind_demo = nil
end

# demo 用の toplevel widget を生成
$twind_demo = TkToplevel.new {|w|
  title("Text Demonstration - Embedded Windows")
  iconname("Embedded Windows")
  positionWindow(w)
}

base_frame = TkFrame.new($twind_demo).pack(:fill=>:both, :expand=>true)

# frame 生成
$twind_buttons = TkFrame.new(base_frame) {|frame|
  TkButton.new(frame) {
    #text '了解'
    text '閉じる'
    command proc{
      tmppath = $twind_demo
      $twind_demo = nil
      tmppath.destroy
    }
  }.pack('side'=>'left', 'expand'=>'yes')

  TkButton.new(frame) {
    text 'コード参照'
    command proc{showCode 'twind'}
  }.pack('side'=>'left', 'expand'=>'yes')
}
$twind_buttons.pack('side'=>'bottom', 'fill'=>'x', 'pady'=>'2m')

# frame 生成
$twind_text = nil
TkFrame.new(base_frame, 'highlightthickness'=>2, 'borderwidth'=>2,
            'relief'=>'sunken') {|f|
  $twind_text = TkText.new(f, 'setgrid'=>'true', 'font'=>$font,
                          'width'=>'70', 'height'=>35, 'wrap'=>'word',
                          'highlightthickness'=>0, 'borderwidth'=>0 ){|t|
    TkScrollbar.new(f) {|s|
      command proc{|*args| t.yview(*args)}
      t.yscrollcommand proc{|first,last| s.set first,last}
    }.pack('side'=>'right', 'fill'=>'y')
  }.pack('expand'=>'yes', 'fill'=>'both')
}.pack('expand'=>'yes', 'fill'=>'both')

# タグ生成
$tag_center = TkTextTag.new($twind_text,
                            'justify' =>'center',
                            'spacing1'=>'5m',
                            'spacing3'=>'5m'  )
$tag_buttons = TkTextTag.new($twind_text,
                             'lmargin1'=>'1c',
                             'lmargin2'=>'1c',
                             'rmargin' =>'1c',
                             'spacing1'=>'3m',
                             'spacing2'=>0,
                             'spacing3'=>0 )

# テキストの生成
$twind_text.insert('end',
                  'テキストwidget上に他のwidgetを組み込むことができます。')
$twind_text.insert('end',
                  '組み込みウィンドウと呼ばれ、任意のwidgetが可能です。')
$twind_text.insert('end',
                  '例えば、ここに2つのボタンwidgetが組み込まれています。')
$twind_text.insert('end', '最初のボタンをクリックすと水平方向のスクロールを')
TkTextWindow.new($twind_text, 'end',
                 'window'=>TkButton.new($twind_text) {
                   #text 'ON'
                   text 'オン'
                   command proc{textWindOn $twind_text,$twind_buttons}
                   cursor 'top_left_arrow'
                 })
$twind_text.insert('end', "にします。また2つめのボタンをクリックすると\n")
$twind_text.insert('end', '水平方向のスクロールを')
TkTextWindow.new($twind_text, 'end',
                 'window'=>TkButton.new($twind_text) {
                   #text 'OFF'
                   text 'オフ'
                   command proc{textWindOff $twind_text}
                   cursor 'top_left_arrow'
                 })
$twind_text.insert('end', 'にします。')

$twind_text.insert('end', 'もうひとつの例です。')
TkTextWindow.new($twind_text, 'end',
                 'window'=>TkButton.new($twind_text) {
                   text 'ここをクリック'
                   command proc{textWindPlot $twind_text}
                   cursor 'top_left_arrow'
                 })
$twind_text.insert('end', 'すると、x-yプロットがここに現れます。')
$mark_plot = TkTextMark.new($twind_text, 'insert')
$mark_plot.gravity='left'
$twind_text.insert('end', 'マウスでデータを描画することができます。')
TkTextWindow.new($twind_text, 'end',
                 'window'=>TkButton.new($twind_text) {
                   text '消去'
                   command proc{textWindDel $twind_text}
                   cursor 'top_left_arrow'
                 })
$twind_text.insert('end', 'をクリックすると元に戻ります。

')

$twind_text.insert('end', '組み込みウィンドウだけをテキストwidget上に、実際の')
$twind_text.insert('end', 'テキストはなしで組み込むことは便利です。')
$twind_text.insert('end', 'この場合は、テキストwidgetはウィンドウマネージャの')
$twind_text.insert('end', 'ように動作します。例えば、ここにはテキストwidgetに')
$twind_text.insert('end', 'よってボタンがきれいに並べられています。')
$twind_text.insert('end', 'これらのボタンで背景色を変えることができます')
$twind_text.insert('end', '("Default"で元の色に戻すことができます)。')
$twind_text.insert('end', '"Short"というボタンをクリックすると文字列の長さが')
$twind_text.insert('end', '変わります。すると自動的にテキストwidgetが')
$twind_text.insert('end', 'レイアウトを整えてくれます。')
$twind_text.insert('end', 'もう一度同じボタンを押すと元に戻ります。

')

TkTextWindow.new($twind_text, 'end',
                 'window'=>TkButton.new($twind_text) {|b|
                   text 'デフォルト'
                   command proc{embDefBg $twind_text}
                   cursor 'top_left_arrow'
                   $tag_buttons.add('end')
                 },
                 'padx'=>3 )
embToggle = TkVariable.new('Short')
TkTextWindow.new($twind_text, 'end',
                 'window'=>TkCheckButton.new($twind_text) {
                   textvariable embToggle
                   indicatoron 0
                   variable embToggle
                   onvalue 'A much longer string'
                   offvalue 'Short'
                   cursor 'top_left_arrow'
                   pady 5
                   padx 2
                 },
                 'padx'=>3,
                 'pady'=>2 )

[ 'AntiqueWhite3', 'Bisque1', 'Bisque2', 'Bisque3', 'Bisque4',
  'SlateBlue3', 'RoyalBlue1', 'SteelBlue2', 'DeepSkyBlue3', 'LightBlue1',
  'DarkSlateGray1', 'Aquamarine2', 'DarkSeaGreen2', 'SeaGreen1',
  'Yellow1', 'IndianRed1', 'IndianRed2', 'Tan1', 'Tan4'
].each{|twind_color|
  TkTextWindow.new($twind_text, 'end',
                   'window'=>TkButton.new($twind_text) {
                     text twind_color
                     cursor 'top_left_arrow'
                     command proc{$twind_text.bg twind_color}
                   },
                   'padx'=>3,
                   'pady'=>2 )
}

# メソッド定義
def textWindOn (w,f)
  if defined? $twind_scroll
    begin
      $twind_scroll.destroy
    rescue
    end
    $twind_scroll = nil
  end

  base = TkWinfo.parent( TkWinfo.parent(w) )
  $twind_scroll = TkScrollbar.new(base) {|s|
    orient 'horizontal'
    command proc{|*args| w.xview(*args)}
    w.xscrollcommand proc{|first,last| s.set first,last}
    w.wrap 'none'
    pack('after'=>f, 'side'=>'bottom', 'fill'=>'x')
  }

  return nil
end

def textWindOff (w)
  if defined? $twind_scroll
    begin
      $twind_scroll.destroy
    rescue
    end
    $twind_scroll = nil
  end
  w.xscrollcommand ''
  w.wrap 'word'
end

def textWindPlot (t)
  if (defined? $twind_plot) && (TkWinfo.exist?($twind_plot))
    return
  end

  $twind_plot = TkCanvas.new(t) {
    relief 'sunken'
    width  450
    height 300
    cursor 'top_left_arrow'
  }

  if $tk_version =~ /^4.*/
    font = '-Adobe-Helvetica-Medium-R-Normal--*-180-*-*-*-*-*-*'
  else
    font = 'Helvetica 18'
  end

  TkcLine.new($twind_plot, 100, 250, 400, 250, 'width'=>2)
  TkcLine.new($twind_plot, 100, 250, 100,  50, 'width'=>2)
  TkcText.new($twind_plot, 225, 20,
              'text'=>"A Simple Plot", 'font'=>font, 'fill'=>'brown')

  (0..10).each {|i|
    x = 100 + (i * 30)
    TkcLine.new($twind_plot, x, 250, x, 245, 'width'=>2)
    TkcText.new($twind_plot, x, 254,
                'text'=>10*i, 'font'=>font, 'anchor'=>'n')
  }
  (0..5).each {|i|
    y = 250 - (i * 40)
    TkcLine.new($twind_plot, 100, y, 105, y, 'width'=>2)
    TkcText.new($twind_plot, 96, y,
                'text'=>"#{i*50}.0", 'font'=>font, 'anchor'=>'e')
  }

  for xx, yy in [[12,56],[20,94],[33,98],[32,120],[61,180],[75,160],[98,223]]
    x = 100 + (3*xx)
    y = 250 - (4*yy)/5
    item = TkcOval.new($twind_plot, x-6, y-6, x+6, y+6,
                       'width'=>1, 'outline'=>'black', 'fill'=>'SkyBlue2')
    item.addtag 'point'
  end

  $twind_plot.itembind('point', 'Any-Enter',
                        proc{$twind_plot.itemconfigure 'current', 'fill', 'red'})
  $twind_plot.itembind('point', 'Any-Leave',
                        proc{$twind_plot.itemconfigure 'current', 'fill', 'SkyBlue2'})
  $twind_plot.itembind('point', '1',
                        proc{|x,y| embPlotDown $twind_plot,x,y}, "%x %y")
  $twind_plot.itembind('point', 'ButtonRelease-1',
                        proc{$twind_plot.dtag 'selected'})
  $twind_plot.bind('B1-Motion',
                    proc{|x,y| embPlotMove $twind_plot,x,y}, "%x %y")
  while ($twind_text.get($mark_plot) =~ /[ \t\n]/)
    $twind_text.delete $mark_plot
  end
  $twind_text.insert $mark_plot,"\n"
  TkTextWindow.new($twind_text, $mark_plot, 'window'=>$twind_plot)
  $tag_center.add $mark_plot
  $twind_text.insert $mark_plot,"\n"
end

$embPlot = {'lastX'=>0, 'lastY'=>0}

def embPlotDown (w, x, y)
  w.dtag 'selected'
  w.addtag_withtag 'selected', 'current'
  w.raise 'current'
  $embPlot['lastX'] = x
  $embPlot['lastY'] = y
end

def embPlotMove (w, x, y)
  w.move 'selected', x - $embPlot['lastX'], y - $embPlot['lastY']
  $embPlot['lastX'] = x
  $embPlot['lastY'] = y
end

def textWindDel (w)
  if (defined? $twind_text) && TkWinfo.exist?($twind_plot)
    $twind_text.delete $twind_plot
    $twind_plot = nil
    while ($twind_text.get($mark_plot) =~ /[ \t\n]/)
      $twind_text.delete $mark_plot
    end
    $twind_text.insert $mark_plot,"  "
  end
end

def embDefBg (w)
  w['background'] = w.configinfo('background')[3]
end
