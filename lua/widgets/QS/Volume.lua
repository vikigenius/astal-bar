local astal = require("astal")
local bind = astal.bind
local Variable = astal.Variable
local Widget = require("astal.gtk3.widget")
local Gtk = require("astal.gtk3").Gtk
local Wp = astal.require("AstalWp")

local Volume = {}
local show_speaker_devices_list = Variable(false)
local show_microphone_devices_list = Variable(false)

local function create_volume_control(type)
  local audio = Wp.get_default().audio
  local device = audio["default_" .. type]

  local scale = Widget.Slider({
    hexpand = true,
    draw_value = false,
    on_dragged = function(self)
      device.volume = self.value
    end,
    value = bind(device, "volume"),
    class_name = bind(device, "mute"):as(function(mute)
      return (mute and "muted" or "")
    end),
  })

  local mute_button = Widget.Button({
    on_clicked = function()
      device.mute = not device.mute
    end,
    class_name = bind(device, "mute"):as(function(mute)
      return "volume-button " .. (mute and "active" or "")
    end),
    child = Widget.Icon({
      icon = bind(device, "mute"):as(function(mute)
        if type == "speaker" then
          return mute and "audio-volume-muted-symbolic" or "audio-volume-high-symbolic"
        else
          return mute and "microphone-disabled-symbolic" or "audio-input-microphone-symbolic"
        end
      end),
    }),
  })

  local expand_button = Widget.Button({
    on_clicked = function()
      if type == "speaker" then
        show_speaker_devices_list:set(not show_speaker_devices_list:get())
      else
        show_microphone_devices_list:set(not show_microphone_devices_list:get())
      end
    end,
    class_name = "expand-button",
    child = Widget.Icon({ icon = "pan-down-symbolic" }),
  })

  return Widget.Box({
    orientation = "VERTICAL",
    spacing = 5,
    Widget.Box({
      class_name = type == "speaker" and "volume-indicator" or "mic-indicator",
      orientation = "HORIZONTAL",
      spacing = 10,
      Widget.Box({
        class_name = "indicator",
        Widget.Icon({
          icon = bind(device, "volume"):as(function(vol)
            if device.mute or vol == 0 then
              return type == "speaker" and "audio-volume-muted-symbolic" or "microphone-disabled-symbolic"
            elseif type == "speaker" then
              if vol < 0.3 then
                return "audio-volume-low-symbolic"
              elseif vol < 0.7 then
                return "audio-volume-medium-symbolic"
              else
                return "audio-volume-high-symbolic"
              end
            else
              return "audio-input-microphone-symbolic"
            end
          end),
        }),
      }),
      Widget.Box({
        class_name = "slider-container",
        hexpand = true,
        scale,
      }),
      mute_button,
      expand_button,
    }),
    Widget.Revealer({
      transition_duration = 200,
      transition_type = "SLIDE_DOWN",
      reveal_child = type == "speaker" and show_speaker_devices_list() or show_microphone_devices_list(),
      Widget.Box({
        class_name = "expanded-menu",
        orientation = "VERTICAL",
        spacing = 5,
        bind(audio, type .. "s"):as(function(devices)
          if not devices then return {} end

          local buttons = {}
          for _, device_item in ipairs(devices) do
            table.insert(buttons, Widget.Button({
              class_name = "device-item",
              child = Widget.Box({
                class_name = bind(device, "id"):as(function(id)
                  return id == device_item.id and "active" or ""
                end),
                Widget.Icon({
                  icon = type == "speaker" and "audio-speakers-symbolic" or "audio-input-microphone-symbolic",
                }),
                Widget.Label({
                  label = device_item.description or "Unknown Device",
                }),
              }),
              on_clicked = function()
                device_item:set_is_default(true)
              end,
            }))
          end
          return buttons
        end),
      }),
    }),
  })
end

function Volume.create_output_slider()
  return create_volume_control("speaker")
end

function Volume.create_input_slider()
  return create_volume_control("microphone")
end

return Volume
