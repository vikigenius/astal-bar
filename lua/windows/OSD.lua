local astal = require("astal")
local Widget = require("astal.gtk3").Widget
local Gtk = require("astal.gtk3").Gtk
local Wp = astal.require("AstalWp")
local bind = astal.bind

local timeout = astal.timeout

local SHOW_TIMEOUT = 1500

local function create_volume_indicator(device, class_name)
  local box = Widget.Box({
    class_name = class_name,
    visible = false,
    Widget.Box({
      class_name = "indicator",
      Widget.Icon({
        icon = bind(device, "volume-icon"),
      }),
      Widget.Label({
        label = bind(device, "volume"):as(function(vol)
          return string.format("%d%%", math.floor((vol or 0) * 100))
        end),
      }),
    }),
    Widget.Box({
      class_name = "slider-container",
      css = "min-width: 140px;",
      Widget.Slider({
        class_name = "volume-slider",
        hexpand = true,
        on_dragged = function(self)
          device.volume = self.value
        end,
        value = bind(device, "volume"),
      }),
    }),
  })

  return {
    box = box,
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
      label = "Muted",
    }),
  })
end

local function create_osd_widget()
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
    show_osd(speaker_vol.box)
  end)

  bind(speaker, "mute"):subscribe(function(muted)
    if muted then
      show_osd(speaker_mute)
    else
      show_osd(speaker_vol.box)
    end
  end)

  bind(mic, "volume"):subscribe(function(vol)
    show_osd(mic_vol.box)
  end)

  bind(mic, "mute"):subscribe(function(muted)
    if muted then
      show_osd(mic_mute)
    else
      show_osd(mic_vol.box)
    end
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
    anchor = Anchor.BOTTOM,
    Widget.Box({
      create_osd_widget(),
    }),
  })
end
