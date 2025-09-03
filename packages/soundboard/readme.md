# Linux Soundboard
A minimal linux soundboard written in bash that plays sounds to discord (or other app like Teams if you implement it).

## Requirements
- [Pipewire](https://wiki.archlinux.org/title/PipeWire)
  - input nodes should be stereo or `pw-play` might not work properly (I use [easyeffects](https://github.com/wwmm/easyeffects))
- [bemenu](https://github.com/Cloudef/bemenu) or [tofi](https://github.com/philj56/tofi)

## Usage
Change the script to fit your needs:  
- `SOUNDBOX_FOLDER`: Folder with the audio files.
- `DEFAULT_VOLUME`: Default ouput volume that can be overwritten in the file name.
- `DMENU`: dmenu implementation to use between bemenu or tofi
- And some other minor settings...

Filename examples:
- [🦖_yoshi-tongue.mp3](https://www.myinstants.com/fr/instant/yoshi-tongue/) (volume: `$DEFAULT_VOLUME`)
- [🪡_hollow-knight-hornet-shaa.v0_2.mp3](https://www.myinstants.com/fr/instant/hornet-shaa-22830/) (volume: 20%)
- [🌞_clair-obscur-expedition-33-monoco-owowow.v1.wav](https://www.myinstants.com/fr/instant/e33-monoco-owowow-47765/) (volume: 100%)

Using the script:
```
Usage: soundboard <subcommand>

Commands:
  gui                Display a bemenu sound picker
  play <filepath>    Play the provided file
  replay             Replay the last file
  stop               Stop all playing files
```


## My personal shortcuts
- `Super`+`:`: `soundboard gui`
- `Super`+`end`: `soundboard stop`
- `Super`+`Shift`+`:`: `soundboard replay`
