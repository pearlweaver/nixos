# Version 26.6.15.1

## Configuring Navidrome (WIP)

- Added the self-hosted service of Navidrome for local music play.
- It is imcomplete, there are still no playlists created (I think I need to do this manually)
- Also I need to find a good player for it too. (Currently just playing local files through strawberry player)

There is also a very important change made in `system/configuration.nix`. It is about giving Navidrome complete access to the home folder. This was giving the same error as when setting up Immich _(unable to read `/home`)_. I tried giving it exclusive access to the ~/Music but it didn't work properly. I will try this again some time.


Also added some plugins for **Nemo File Manager** in `home/home.nix`
