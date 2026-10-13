# MinAudio::Context + MinAudio::DeviceInfo — device enumeration
# (ma_context / ma_context_get_devices). Query what playback/capture
# hardware exists without opening an Engine:
#
#   devices = MinAudio::Context.devices
#   devices[:playback].each { |d| puts d.name }
#
# The context is closed when the block/method scope ends — the info
# arrays are copied out before uninit, so the returned structs stay
# valid. Device ids are opaque 64-byte blobs (ma_device_id is a
# backend-dependent union), passable to future open-by-id APIs.

module MinAudio
  class DeviceInfo
    getter name : String
    # Opaque ma_device_id blob (64 bytes on every current backend).
    getter id : Bytes

    # Internal: built by Context.devices from the raw ma_device_info.
    def initialize(@name : String, @id : Bytes)
    end
  end

  class Context
    @buf : Bytes
    @closed : Bool = false

    def initialize
      @buf = Bytes.new(LibMinAudio.sizeof_context)
      MinAudio.check(
        LibMinAudio.context_init(
          Pointer(Void).null, 0, Pointer(Void).null, @buf),
        "context init")
    end

    def to_unsafe : Void*
      @buf.to_unsafe.as(Void*)
    end

    # Enumerate devices on a fresh context: `devices` and `names` are the
    # convenience entry points.
    def self.devices : {playback: Array(DeviceInfo), capture: Array(DeviceInfo)}
      ctx = new
      begin
        ctx.devices
      ensure
        ctx.close
      end
    end

    # Playback device names on this machine (the 99% case).
    def self.names : Array(String)
      devices[:playback].map(&.name)
    end

    def devices : {playback: Array(DeviceInfo), capture: Array(DeviceInfo)}
      pb = Pointer(Void).null
      cap = Pointer(Void).null
      pb_n = uninitialized UInt32
      cap_n = uninitialized UInt32
      MinAudio.check(
        LibMinAudio.context_get_devices(
          to_unsafe, pointerof(pb), pointerof(pb_n),
          pointerof(cap), pointerof(cap_n)),
        "enumerate devices")
      id_size = LibMinAudio.sizeof_device_id
      playback = Array(DeviceInfo).new(pb_n.to_i32!) do |i|
        info = (pb + i).as(Void*)
        id = Bytes.new(id_size)
        LibMinAudio.device_info_id_copy(info, id.to_unsafe)
        DeviceInfo.new(String.new(LibMinAudio.device_info_name(info)), id)
      end
      capture = Array(DeviceInfo).new(cap_n.to_i32!) do |i|
        info = (cap + i).as(Void*)
        id = Bytes.new(id_size)
        LibMinAudio.device_info_id_copy(info, id.to_unsafe)
        DeviceInfo.new(String.new(LibMinAudio.device_info_name(info)), id)
      end
      {playback: playback, capture: capture}
    end

    def close : Nil
      return if @closed
      LibMinAudio.context_uninit(to_unsafe)
      @closed = true
    end

    def finalize
      close
    end
  end
end
