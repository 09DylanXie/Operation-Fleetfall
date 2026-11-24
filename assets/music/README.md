# Soundtrack

Drop soundtrack files here (`.mp3`, `.ogg` or `.wav`, e.g. tracks from Pixabay). The `Music`
autoload (`scripts/audio/music.gd`) finds every track in this folder on start-up and plays
them as a shuffled playlist on the "Music" bus, looping the whole list. No code changes or
scene edits are needed: open the project in Godot once (or run it) so the new files are
imported, then commit them.

- Volume: `Music.VOLUME_DB` (default `-10` dB, under the effects).
- Gap between tracks: `Music.GAP` (seconds).
- Keep file names simple (letters, numbers, `_`, `-`); spaces work but are awkward in git.
- Pixabay tracks fall under the Pixabay Content License (no attribution required), but list
  them in `CREDITS.md` here if you want to credit the artists.
