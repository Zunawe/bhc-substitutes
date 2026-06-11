# Mesen
- **Consoles**: GB, GBC, GBA, NES
- **Platforms**: Windows, Mac, Linux
- **Notes**:
  - Other consoles supported by Mesen could be added.
- **Instructions**:
  1. Download `connector_bizhawkclient_mesen2.js` either by opening the file in GitHub and clicking the "Download raw file" button or by downloading the repo and extracting the file.
  2. Put the Lua script in `Archipelago/data/lua/`.
  3. Open your ROM in Mesen.
  4. In Mesen, go to `Debug > Script Window` in the menu. By default, this will open and run an example script. You can click the Stop Script button to get rid of the stuff it draws on your screen.
  5. In the Script Window, open `Script > Settings`. You can choose what happens when you open the script window in the future, including whether it opens a recent script and whether it automatically runs the script when open.
  6. At the bottom, check `Allow access to I/O and OS functions` and `Allow network access`. We need these for the script to communicate with the client window.
  7. Save the settings, and in the Script Window go to `File > Open`.
  8. If you need to manually start the script, click the Run Script button in the toolbar at the top.
