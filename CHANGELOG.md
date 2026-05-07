# Version 26.5.7.1

-  Configured C++ **gcc** compiler and **raylib** (Haven't implemented debugger and clang error handling)
- Installed **Steam** and **Heroic Launcher**
- Installed **UnityHub**
- Was trying to do something about raylib in `./modules/shell.nix` but it didn't work. The code is there, just the line to import that file is commented inside `configuration.nix`

For raylib to work, go to `/etc/nixos` directory and run the command `nix develop`. It will start a terminal session. From there, go to the directory containing your raylib project and compile it through this terminal session. 
Use the following flags: `-lraylib -lGL -lm -lpthread -ldl -lrt -lX11`