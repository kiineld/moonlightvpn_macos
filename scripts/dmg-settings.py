# dmgbuild settings for the installer window.
#
# dmgbuild writes the volume's .DS_Store itself, in pure Python, so the styled
# layout needs no Finder and works on a headless CI runner — which is where the
# released images are actually built.
import os.path

application = defines.get("app", "build/Moonlight.app")  # noqa: F821
appname = os.path.basename(application)

format = "UDZO"
compression_level = 9
files = [application]
symlinks = {"Applications": "/Applications"}
badge_icon = defines.get("icon", "Resources/AppIcon.icns")  # noqa: F821

# The window and the backdrop are the same 660x420; the icon row sits at y=250,
# which is where make-dmg-background.swift draws the arrow between them.
background = defines.get("background", "build/dmg-background.png")  # noqa: F821
window_rect = ((300, 160), (660, 420))
default_view = "icon-view"
icon_size = 110
text_size = 13
icon_locations = {appname: (190, 250), "Applications": (470, 250)}

show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
