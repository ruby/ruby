# Face

With the `Reline::Face` class, you can modify the text color and text decorations in your terminal emulator.
This is primarily used to customize the appearance of the method completion dialog in IRB.

## Usage

### ex: Change the background color of the completion dialog cyan to blue

```ruby
Reline::Face.config(:completion_dialog) do |conf|
  conf.define :default, foreground: :white, background: :blue
  #                                                     ^^^^^ `:cyan` by default
  conf.define :enhanced, foreground: :white, background: :magenta
  conf.define :scrollbar, foreground: :white, background: :blue
end
```

If you provide the above code to an IRB session in some way, you can apply the configuration.
It's generally done by writing it in `.irbrc`.

Regarding `.irbrc`, please refer to the following link: [https://docs.ruby-lang.org/en/master/IRB.html](https://docs.ruby-lang.org/en/master/IRB.html)

## Available parameters

`Reline::Face` internally creates SGR (Select Graphic Rendition) code according to the block parameter of `Reline::Face.config` method.

| Key         | Value             | SGR Code (numeric part following "\e[")|
|:------------|:------------------|-----:|
| :foreground | :black            | 30   |
|             | :red              | 31   |
|             | :green            | 32   |
|             | :yellow           | 33   |
|             | :blue             | 34   |
|             | :magenta          | 35   |
|             | :cyan             | 36   |
|             | :white            | 37   |
|             | :bright_black     | 90   |
|             | :gray             | 90   |
|             | :bright_red       | 91   |
|             | :bright_green     | 92   |
|             | :bright_yellow    | 93   |
|             | :bright_blue      | 94   |
|             | :bright_magenta   | 95   |
|             | :bright_cyan      | 96   |
|             | :bright_white     | 97   |
| :background | :black            | 40   |
|             | :red              | 41   |
|             | :green            | 42   |
|             | :yellow           | 43   |
|             | :blue             | 44   |
|             | :magenta          | 45   |
|             | :cyan             | 46   |
|             | :white            | 47   |
|             | :bright_black     | 100  |
|             | :gray             | 100  |
|             | :bright_red       | 101  |
|             | :bright_green     | 102  |
|             | :bright_yellow    | 103  |
|             | :bright_blue      | 104  |
|             | :bright_magenta   | 105  |
|             | :bright_cyan      | 106  |
|             | :bright_white     | 107  |
| :style      | :reset            | 0    |
|             | :bold             | 1    |
|             | :faint            | 2    |
|             | :italicized       | 3    |
|             | :underlined       | 4    |
|             | :slowly_blinking  | 5    |
|             | :blinking         | 5    |
|             | :rapidly_blinking | 6    |
|             | :negative         | 7    |
|             | :concealed        | 8    |
|             | :crossed_out      | 9    |

- The value for `:style` can be both a Symbol and an Array
    ```ruby
      # Single symbol
      conf.define :default, style: :bold
      # Array
      conf.define :default, style: [:bold, :negative]
    ```
- The availability of specific SGR codes depends on your terminal emulator
- You can specify a hex color code to `:foreground` and `:background` color like `foreground: "#FF1020"`. Its availability also depends on your terminal emulator

## Debugging

You can see the current Face configuration by `Reline::Face.configs` method

Example:

```ruby
irb(main):001:0> Reline::Face.configs
=>
{:default=>
  {:default=>{:style=>:reset, :escape_sequence=>"\e[0m"},
   :enhanced=>{:style=>:reset, :escape_sequence=>"\e[0m"},
   :scrollbar=>{:style=>:reset, :escape_sequence=>"\e[0m"}},
 :completion_dialog=>
  {:default=>{:foreground=>:white, :background=>:cyan, :escape_sequence=>"\e[0m\e[37;46m"},
   :enhanced=>{:foreground=>:white, :background=>:magenta, :escape_sequence=>"\e[0m\e[37;45m"},
   :scrollbar=>{:foreground=>:white, :background=>:cyan, :escape_sequence=>"\e[0m\e[37;46m"}}}
```

## 256-Color and TrueColor

Reline will automatically detect if your terminal emulator supports truecolor with `ENV['COLORTERM] in 'truecolor' | '24bit'`. When this env is not set, Reline will fallback to 256-color.
If your terminal emulator supports truecolor but does not set COLORTERM env, add this line to `.irbrc`.
```ruby
Reline::Face.force_truecolor
```
