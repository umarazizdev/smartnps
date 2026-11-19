#if canImport(google_maps_flutter_ios_sdk11_objc)
  import google_maps_flutter_ios_sdk11_objc
#endif

protocol MapEventDelegate: AnyObject, MapsCallbackApiProtocol {}
