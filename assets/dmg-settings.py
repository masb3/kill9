# Layout for Kill9.dmg, read by dmgbuild (see build-app.sh).
# Paths are passed in with -D so this file doesn't depend on the working directory.
import os

app = defines["app"]            # path to Kill9.app
assets = defines["assets"]      # this folder
app_name = os.path.basename(app)

format = "ULFO"                 # lzfse-compressed, macOS 10.11+
filesystem = "APFS"
files = [app]
symlinks = {"Applications": "/Applications"}
hide_extensions = [app_name]

icon = os.path.join(assets, "AppIcon.icns")  # disk icon in Finder and on the desktop
background = os.path.join(assets, "dmg-background.tiff")

# Window matches the 660x400 background; icon centres line up with its arrow.
window_rect = ((200, 120), (660, 400))
icon_size = 128
text_size = 13
icon_locations = {app_name: (170, 190), "Applications": (490, 190)}

show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
default_view = "icon-view"
show_icon_preview = False
arrange_by = None
