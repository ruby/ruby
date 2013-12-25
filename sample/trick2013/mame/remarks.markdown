### Remarks

Run the program under a platform that `/dev/dsp` is available.
For example, if you are using pulseaudio, use `padsp`:

    padsp ruby entry.rb

Please see Limitation if you want to run this program on os x.

I confirmed the following platforms.

* ruby 2.0.0p0 (2013-02-24 revision 39474) [x86\_64-linux]
* ruby 1.9.3p194 (2012-04-20 revision 35410) [x86\_64-linux]
* ruby 1.9.3p327 (2012-11-10 revision 37606) [x86\_64-darwin10.8.0]

For those who are lazy, I'm attaching a screencast.

### Description

This program is a music-box quine.
It prints itself with playing "Jesu, Joy of Man's Desiring".

### Internal

Like a real music box, this program consists of a mechanical part (code) and a piano roll.
In the piano roll, `#` represents a pin that hits a note, and `|` represents a slur.
The leftmost column corresponds 110Hz (low A).
Every column corresponds a semitone higher than the left one.

This program uses [the frequency modulation synthesis](http://en.wikipedia.org/wiki/Frequency_modulation_synthesis) to play the sound like a music-box.
You can create a different-sounding tone by changing the parameter.
For example, the following will play the sound like a harpsichord.

    padsp ruby entry.rb 2.0

Note that this program does *not* use an idiom to remove whitespace, such as `.split.join`.  All newlines and spaces do not violate any of the Ruby syntax rules.

### Limitation

On os x, `/dev/dsp` is not available.
You have to use sox by replacing the following part:

    open("/dev/dsp","wb")

with:

    IO.popen("./pl","wb")