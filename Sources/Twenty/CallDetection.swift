import IOKit.pwr_mgt
import CoreAudio
import CoreMediaIO

// No permissions needed: these only ask whether a device is busy.

func cameraInUse() -> Bool {
    let system = CMIOObjectID(kCMIOObjectSystemObject)
    var addr = CMIOObjectPropertyAddress(mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
                                        mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                                        mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
    var size: UInt32 = 0
    guard CMIOObjectGetPropertyDataSize(system, &addr, 0, nil, &size) == 0 else { return false }
    var ids = [CMIODeviceID](repeating: 0, count: Int(size) / MemoryLayout<CMIODeviceID>.size)
    guard CMIOObjectGetPropertyData(system, &addr, 0, nil, size, &size, &ids) == 0 else { return false }
    addr.mSelector = CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere)
    return ids.contains { id in
        var running: UInt32 = 0, s = UInt32(MemoryLayout<UInt32>.size)
        return CMIOObjectGetPropertyData(id, &addr, 0, nil, s, &s, &running) == 0 && running != 0
    }
}

// Per-process input check, so music playing on AirPods doesn't count as a call.
func micInUse() -> Bool {
    let system = AudioObjectID(kAudioObjectSystemObject)
    var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyProcessObjectList,
                                          mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(system, &addr, 0, nil, &size) == noErr else { return false }
    var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
    guard AudioObjectGetPropertyData(system, &addr, 0, nil, &size, &ids) == noErr else { return false }
    addr.mSelector = kAudioProcessPropertyIsRunningInput
    return ids.contains { id in
        var running: UInt32 = 0, s = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(id, &addr, 0, nil, &s, &running) == noErr && running != 0
    }
}

// Video players (browsers, VLC, QuickTime) hold a display-sleep assertion while playing.
func videoPlaying() -> Bool {
    var raw: Unmanaged<CFDictionary>?
    guard IOPMCopyAssertionsByProcess(&raw) == kIOReturnSuccess,
          let byPid = raw?.takeRetainedValue() as? [AnyHashable: [[String: Any]]] else { return false }
    return byPid.values.joined().contains {
        $0["AssertionTrueType"] as? String == kIOPMAssertionTypePreventUserIdleDisplaySleep as String
    }
}
