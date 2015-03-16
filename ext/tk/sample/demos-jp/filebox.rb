# -*- coding: utf-8 -*-
#
# widget demo prompts the user to select a file (called by 'widget')
#

# toplevel widget が存在すれば削除する
if defined?($filebox_demo) && $entry2_demo
  $filebox_demo.destroy
  $filebox_demo = nil
end

# demo 用の toplevel widget を生成
$filebox_demo = TkToplevel.new {|w|
  title("File Selection Dialogs")
  iconname("filebox")
  positionWindow(w)
}

base_frame = TkFrame.new($filebox_demo).pack(:fill=>:both, :expand=>true)

# label 生成
TkLabel.new(base_frame,'font'=>$font,'wraplength'=>'4i','justify'=>'left',
            'text'=>"エントリにファイル名を直接入力するか、\"Browse\" ボタンを押してファイル選択ダイアログからファイル名を選んで下さい。").pack('side'=>'top')

# frame 生成
TkFrame.new(base_frame) {|frame|
  TkButton.new(frame) {
    #text '了解'
    text '閉じる'
    command proc{
      tmppath = $filebox_demo
      $filebox_demo = nil
      tmppath.destroy
    }
  }.pack('side'=>'left', 'expand'=>'yes')

  TkButton.new(frame) {
    text 'コード参照'
    command proc{showCode 'filebox'}
  }.pack('side'=>'left', 'expand'=>'yes')
}.pack('side'=>'bottom', 'fill'=>'x', 'pady'=>'2m')

# frame 生成
['開く', '保存'].each{|type|
  TkFrame.new(base_frame) {|f|
    TkLabel.new(f, 'text'=>"ファイルを#{type}: ", 'anchor'=>'e')\
    .pack('side'=>'left')

    TkEntry.new(f, 'width'=>20) {|e|
      pack('side'=>'left', 'expand'=>'yes', 'fill'=>'x')

      TkButton.new(f, 'text'=>'Browse ...',
                   'command'=>proc{fileDialog base_frame,e,type})\
      .pack('side'=>'left')
    }

    pack('fill'=>'x', 'padx'=>'1c', 'pady'=>3)
  }
}

$tk_strictMotif = TkVarAccess.new('tk_strictMotif')
if ($tk_platform['platform'] == 'unix')
  TkCheckButton.new(base_frame,
                    'text'=>'Motifスタイルのダイアログを用いる',
                    'variable'=>$tk_strictMotif,
                    'onvalue'=>1, 'offvalue'=>0 ).pack('anchor'=>'c')
end

def fileDialog(w,ent,operation)
  #    Type names         Extension(s)             Mac File Type(s)
  #
  #--------------------------------------------------------
  types = [
    ['Text files',       ['.txt','.doc']          ],
    ['Text files',       [],                      'TEXT' ],
    ['Ruby Scripts',     ['.rb'],                 'TEXT' ],
    ['Tcl Scripts',      ['.tcl'],                'TEXT' ],
    ['C Source Files',   ['.c','.h']              ],
    ['All Source Files', ['.rb','.tcl','.c','.h'] ],
    ['Image Files',      ['.gif']                 ],
    ['Image Files',      ['.jpeg','.jpg']         ],
    ['Image Files',      [],                      ['GIFF','JPEG']],
    ['All files',        '*'                      ]
  ]

  if operation == '開く'
    file = Tk.getOpenFile('filetypes'=>types, 'parent'=>w)
  else
    file = Tk.getSaveFile('filetypes'=>types, 'parent'=>w,
                          'initialfile'=>'Untitled',
                          'defaultextension'=>'.txt')
  end
  if file != ""
    ent.delete 0, 'end'
    ent.insert 0, file
    # ent.xview 'end'
    Tk.update_idletasks # need this for Tk::Tile::Entry
                        # (to find right position of 'xview').
    ent.xview(ent.index('end'))
  end
end

