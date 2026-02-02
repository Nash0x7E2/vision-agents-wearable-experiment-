# Known runtime issues

## SwiftProtobuf duplicate class warnings

You may see Objective-C runtime warnings such as:

```
Class _TtC13SwiftProtobuf17AnyMessageStorage is implemented in both .../MWDATCore.framework/MWDATCore and .../rayban_agents.debug.dylib. One of the duplicates must be removed or renamed.
```

**Cause:** MWDATCore is consumed as a prebuilt XCFramework that embeds SwiftProtobuf. The app also links StreamVideo (stream-video-swift), which depends on SwiftProtobuf via SPM. Both the framework and the app binary therefore contain SwiftProtobuf, leading to duplicate class definitions at runtime.

**Impact:** Possible spurious casting failures or rare crashes when types cross the app/framework boundary.

**Mitigation (app-side):** None. To resolve properly, the Meta Wearables DAT (meta-wearables-dat-ios) package would need to provide a build of MWDATCore that does not embed SwiftProtobuf and instead declares it as a dependency, so the app supplies a single copy. Consider requesting this from the MWDAT maintainers if it causes issues.

---

## Thread performance checker / priority inversion

You may see:

```
Thread Performance Checker: Thread running at User-initiated quality-of-service class waiting on a lower QoS thread running at Default quality-of-service class.
```

The backtrace points into MWDATCore (`BackgroundThread`, `ARCStreamLoader`, `ACDCBTCTransportLink`).

**Cause:** MWDATCore uses a shared background thread at default QoS. When the app calls into the SDK from a user-initiated context (e.g. UI or main actor), that high-QoS thread can block on the SDK’s default-QoS thread, causing a priority inversion.

**Mitigation (app-side):** MWDAT-related work that may block (e.g. stream start, connection) is dispatched to a default-QoS queue before calling into the SDK, so the blocking does not occur on a user-initiated thread. The inversion can still occur inside MWDATCore; a full fix would require the SDK to align its background thread QoS with caller expectations.
