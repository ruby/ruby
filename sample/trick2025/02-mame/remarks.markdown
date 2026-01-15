# A Lesser "Patch" Program

This program is a minimalistic version of the traditional "patch" command, which looks like a patch.

## Usage as a "Patch" Command

The program reads a unified diff file from standard input and applies the changes to the specified files.

To apply `test.patch` to `sample.rb`, use the following commands:

```
$ cp sample.orig.rb sample.rb
$ ruby entry.rb < test.patch
```

After running these commands, verify that `sample.rb` has been modified.

## Usage as a Patch File

Interestingly, this program is not just a patch-like tools -- it *is* a patch.
This duality allows it to be applied like a regular patch file.

The following will create a file named pd.rb.

```
$ patch < entry.rb
```

Alternatively, you can achieve the same result using `entry.rb`:

```
$ ruby entry.rb < entry.rb
```

The generated `pd.rb` produces a new patch.

```
$ ruby pd.rb
```

The produced patch is self-referential, targeting `pd.rb` itself.
To apply it:

```
$ ruby pd.rb | ruby entry.rb
```

You'll notice the `p` logo rotates slightly counterclockwise.

The modified `pd.rb` outputs the patch for itself again, apply the patch repeatedly--a total of 33 times!

## From `p` to `d`

The center `p` logo symbolizes a "patch."
When rotated 180 degrees, it resembles a `d`, signifying a transformation in functionality.
`pd.rb` now operates as a simplified "diff" command:

```
$ ruby pd.rb
usage: pd.rb File File

$ ruby pd.rb sample.orig.rb sample.rb
--- sample.orig.rb
+++ sample.rb
...
```

## Integration with Git

The patches are compatible with Git's `git am` command, which imports patches in mbox format.

Start fresh by removing `pd.rb` and initializing a Git repository:

```
$ rm -f pd.rb
$ git init
Initialized empty Git repository in /home/...
```

And import `entry.rb` as a patch to the repository:

```
$ git am --committer-date-is-author-date entry.rb
Applying: +(/.{40}/));exit].gsub(/X.*X|\n(\h+\s)?\+?/,E=""))#_TRICK2025_]}
applying to an empty history
```

Verify the commit history:

```
$ git log
commit 1e32693f11c1df77bd797c7b3e9f108a3e139824 (HEAD -> main)
Author: pd (`) <pd-@example.com>
Date:   Wed Jan 1 00:00:00 2025 +0000

    +an(/.{40}/));exit].gsub(/X.*X|\n(\h+\s)?\+?/,E=""))#TRICK2025]}
```

Notice that the Author and Date are properly set.

To apply subsequent patches:

```
$ for i in `seq 0 32`; do ruby pd.rb | git am --committer-date-is-author-date; done
```

*(A fun details: you will see the `b` logo!)*

Now, view a commit history by the following command:

```
$ git log --oneline
```

You will rediscover the original `entry.rb` unexpectedly.

If you set `--committer-date-is-author-date` appropriately, you should be able to run the output of `git log --oneline` as is.

Try this unusual command:

```
$ git log --oneline | ruby - test.patch
```

## A Little Something Extra

Interestingly, `pd.rb` -- functioning as a diff command -- is a patch to itself.
Reveal hidden details with:

```
$ ruby entry.rb pd.rb
$ ruby pd.rb
```

Can you spot the difference?

## Limitations

* I tested it with ruby 3.3.6, git 2.45.2, and GNU patch 2.7.6.
* No error check at all. The lesser patch do not care if there is a discrepancy between what is written in the patch and the input file, and will write over the existing file without prompt.
* It is assumed that the text files have a new line at the end.
