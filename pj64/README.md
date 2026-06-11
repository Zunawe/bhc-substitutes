# Project64 and Luna's Project64
- **Consoles**: N64
- **Platforms (Project64)**: Windows
- **Platforms (Luna's Project64)**: Windows, Linux (Wine), Mac (Wine, Untested)
- **Notes**:
  - The "vanilla" Project64 program has a more fleshed out scripting API than Luna's Project64, so the script was written and tested in Luna's, but it _should_ work in either.
  - Tested on Luna's Project64 v3.6.5 and Project64 3.0.1-5664-2df3434.
- **Instructions**:
  1. Download `connector_bizhawkclient_pj64.js` either by opening the file in GitHub and clicking the "Download raw file" button or by downloading the repo and extracting the file.
  2. Open Project64.
  3. If you're using Luna's Project64, click `Debugger > Enable Debugger` in the menu. If you're using the original Project64, go to `Options > Configuration` in the menu. Then in General Settings, uncheck `Hide advanced settings`. Then go to Advanced and check `Enable debugger`. Then click OK to close the Configuration window.
  4. Open `Debugger > Scripts...` in the main emulator menu.
  5. In the new scripts window, click the `...` button in the bottom left corner to open Project64's scripts folder in your file browser. Move the connector script into this folder, and it should appear in the left column of the scripts window.
  6. Double-click the script name or select it and click the `Run` button.
