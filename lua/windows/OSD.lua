local astal = require("astal")
local Widget = require("astal.gtk3").Widget
local Gtk = require("astal.gtk3").Gtk
local Wp = astal.require("AstalWp")
local bind = astal.bind

local timeout = astal.timeout

local SHOW_TIMEOUT = 1500

local function create_volume_indicator(device, class_name)
  local progress = Gtk.ProgressBar()

  local box = Widget.Box({
    class_name = class_name,
    visible = false,
    Widget.Icon({
      icon = bind(device, "volume-icon"),
    }),
    Widget.Box({
      class_name = "progress-bar",
      progress,
    }),
    Widget.Label({
      label = bind(device, "volume"):as(function(vol)
        return string.format("%d%%", math.floor((vol or 0) * 100))
      end),
    }),
  })

  return {
    box = box,
    progress = progress,
  }
end

local function create_mute_indicator(device, class_name)
  return Widget.Box({
    class_name = class_name .. "-mute",
    visible = false,
    Widget.Icon({
      icon = bind(device, "volume-icon"),
    }),
    Widget.Label({
      label = bind(device, "mute"):as(function(muted)
        return muted and "Muted" or "Unmuted"
      end),
    }),
  })
end

local function OnScreenProgress()
  local speaker = Wp.get_default().audio.default_speaker
  local mic = Wp.get_default().audio.default_microphone

  local speaker_vol = create_volume_indicator(speaker, "volume-indicator")
  local mic_vol = create_volume_indicator(mic, "mic-indicator")
  local speaker_mute = create_mute_indicator(speaker, "volume-indicator")
  local mic_mute = create_mute_indicator(mic, "mic-indicator")

  local current_timeout = nil

  local function hide_all()
    speaker_vol.box.visible = false
    mic_vol.box.visible = false
    speaker_mute.visible = false
    mic_mute.visible = false
  end

  local function show_osd(widget)
    hide_all()
    widget.visible = true

    if current_timeout then
      current_timeout:cancel()
    end

    current_timeout = timeout(SHOW_TIMEOUT, function()
      widget.visible = false
      current_timeout = nil
    end)
  end

  bind(speaker, "volume"):subscribe(function(vol)
    speaker_vol.progress.fraction = vol or 0
    show_osd(speaker_vol.box)
  end)

  bind(speaker, "mute"):subscribe(function(muted)
    show_osd(speaker_mute)
  end)

  bind(mic, "volume"):subscribe(function(vol)
    mic_vol.progress.fraction = vol or 0
    show_osd(mic_vol.box)
  end)

  bind(mic, "mute"):subscribe(function(muted)
    show_osd(mic_mute)
  end)

  return Widget.Box({
    class_name = "OSD",
    vertical = true,
    speaker_vol.box,
    speaker_mute,
    mic_vol.box,
    mic_mute,
  })
end

return function(gdkmonitor)
  local Anchor = astal.require("Astal").WindowAnchor

  return Widget.Window({
    class_name = "OSDWindow",
    gdkmonitor = gdkmonitor,
    anchor = Anchor.CENTER,
    Widget.Box({
      OnScreenProgress(),
    }),
  })
end
