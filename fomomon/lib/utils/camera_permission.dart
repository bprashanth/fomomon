// Triggers the browser camera-permission dialog on web before the camera
// plugin enumerates devices. On native, this is a no-op — the camera plugin
// handles permissions internally.
//
// Background: camera_web's availableCameras() calls enumerateDevices(), which
// does NOT prompt for permission. The dialog only appears when getUserMedia()
// is called (inside CameraController.initialize()). If enumerateDevices()
// returns an empty list (common on first visit before permission is granted),
// the code crashes before ever reaching initialize() — so the user never sees
// a permission prompt. Calling getUserMedia() here first ensures the dialog
// appears, and enumerateDevices() then returns valid cameras.
export 'camera_permission_stub.dart'
    if (dart.library.html) 'camera_permission_web.dart';
