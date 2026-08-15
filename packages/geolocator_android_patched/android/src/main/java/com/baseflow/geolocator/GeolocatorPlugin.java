package com.baseflow.geolocator;

import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.content.ServiceConnection;
import android.os.Handler;
import android.os.IBinder;
import android.os.Looper;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;

import com.baseflow.geolocator.location.GeolocationManager;
import com.baseflow.geolocator.location.LocationAccuracyManager;
import com.baseflow.geolocator.permission.PermissionManager;

import java.util.ArrayList;
import java.util.List;

import io.flutter.Log;
import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.embedding.engine.plugins.activity.ActivityAware;
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding;

/** GeolocatorPlugin */
public class GeolocatorPlugin implements FlutterPlugin, ActivityAware {

  private static final String TAG = "FlutterGeolocator";
  private final PermissionManager permissionManager;
  private final GeolocationManager geolocationManager;
  private final LocationAccuracyManager locationAccuracyManager;

  @Nullable private GeolocatorLocationService foregroundLocationService;

  @Nullable private MethodCallHandlerImpl methodCallHandler;

  @Nullable private StreamHandlerImpl streamHandler;
  @Nullable private Context applicationContext;
  private boolean serviceBindRequested = false;
  private boolean isBinding = false;
  private final List<Runnable> pendingAfterBind = new ArrayList<>();
  private final Handler mainHandler = new Handler(Looper.getMainLooper());

  private final ServiceConnection serviceConnection =
      new ServiceConnection() {

        @Override
        public void onServiceConnected(ComponentName name, IBinder service) {
          Log.d(TAG, "Geolocator foreground service connected");
          if (service instanceof GeolocatorLocationService.LocalBinder) {
            initialize(((GeolocatorLocationService.LocalBinder) service).getLocationService());
          }
          isBinding = false;
          flushPendingAfterBind();
        }

        @Override
        public void onServiceDisconnected(ComponentName name) {
          Log.d(TAG, "Geolocator foreground service disconnected");
          if (foregroundLocationService != null) {
            foregroundLocationService.setActivity(null);
            foregroundLocationService = null;
          }
          isBinding = false;
          serviceBindRequested = false;
        }
      };
  @Nullable private LocationServiceHandlerImpl locationServiceHandler;

  @Nullable private ActivityPluginBinding pluginBinding;

  public GeolocatorPlugin() {
    permissionManager = PermissionManager.getInstance();
    geolocationManager = GeolocationManager.getInstance();
    locationAccuracyManager = LocationAccuracyManager.getInstance();
  }

  @Override
  public void onAttachedToEngine(@NonNull FlutterPluginBinding flutterPluginBinding) {
    applicationContext = flutterPluginBinding.getApplicationContext();
    methodCallHandler =
        new MethodCallHandlerImpl(
            this.permissionManager, this.geolocationManager, this.locationAccuracyManager);
    methodCallHandler.startListening(
        flutterPluginBinding.getApplicationContext(), flutterPluginBinding.getBinaryMessenger());
    streamHandler = new StreamHandlerImpl(this.permissionManager, this.geolocationManager);
    streamHandler.setForegroundServiceBinder(this::ensureForegroundServiceBound);
    streamHandler.startListening(
        flutterPluginBinding.getApplicationContext(), flutterPluginBinding.getBinaryMessenger());

    locationServiceHandler = new LocationServiceHandlerImpl();
    locationServiceHandler.setContext(flutterPluginBinding.getApplicationContext());
    locationServiceHandler.startListening(
        flutterPluginBinding.getApplicationContext(), flutterPluginBinding.getBinaryMessenger());
  }

  @Override
  public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
    unbindForegroundService(binding.getApplicationContext());
    dispose();
    applicationContext = null;
  }

  @Override
  public void onAttachedToActivity(@NonNull ActivityPluginBinding binding) {
    Log.d(TAG, "Attaching Geolocator to activity");
    this.pluginBinding = binding;
    registerListeners();
    if (methodCallHandler != null) {
      methodCallHandler.setActivity(binding.getActivity());
    }
    if (streamHandler != null) {
      streamHandler.setActivity(binding.getActivity());
    }
    if (foregroundLocationService != null) {
      foregroundLocationService.setActivity(pluginBinding.getActivity());
    }
  }

  @Override
  public void onDetachedFromActivityForConfigChanges() {
    onDetachedFromActivity();
  }

  @Override
  public void onReattachedToActivityForConfigChanges(@NonNull ActivityPluginBinding binding) {
    onAttachedToActivity(binding);
  }

  @Override
  public void onDetachedFromActivity() {
    Log.d(TAG, "Detaching Geolocator from activity");
    deregisterListeners();
    if (methodCallHandler != null) {
      methodCallHandler.setActivity(null);
    }
    if (streamHandler != null) {
      streamHandler.setActivity(null);
    }
    if (foregroundLocationService != null) {
      foregroundLocationService.setActivity(null);
    }
    if (pluginBinding != null) {
      pluginBinding = null;
    }
  }

  private void registerListeners() {
    if (pluginBinding != null) {
      pluginBinding.addActivityResultListener(this.geolocationManager);
      pluginBinding.addRequestPermissionsResultListener(this.permissionManager);
    }
  }

  private void deregisterListeners() {
    if (pluginBinding != null) {
      pluginBinding.removeActivityResultListener(this.geolocationManager);
      pluginBinding.removeRequestPermissionsResultListener(this.permissionManager);
    }
  }

  void ensureForegroundServiceBound(@Nullable Runnable whenReady) {
    if (foregroundLocationService != null) {
      if (whenReady != null) {
        whenReady.run();
      }
      return;
    }
    if (whenReady != null) {
      pendingAfterBind.add(whenReady);
    }
    if (isBinding || applicationContext == null) {
      return;
    }
    Log.d(TAG, "Geolocator binding location service");
    bindForegroundService(applicationContext);
  }

  private void bindForegroundService(Context context) {
    if (serviceBindRequested) {
      return;
    }
    serviceBindRequested = true;
    isBinding = true;
    context.bindService(
        new Intent(context, GeolocatorLocationService.class),
        serviceConnection,
        Context.BIND_AUTO_CREATE);
  }

  private void unbindForegroundService(Context context) {
    pendingAfterBind.clear();
    if (!serviceBindRequested) {
      return;
    }
    try {
      if (foregroundLocationService != null) {
        foregroundLocationService.flutterEngineDisconnected();
      }
      context.unbindService(serviceConnection);
    } catch (IllegalArgumentException e) {
      Log.w(TAG, "Geolocator service already unbound: " + e.getMessage());
    }
    serviceBindRequested = false;
    isBinding = false;
    foregroundLocationService = null;
  }

  private void flushPendingAfterBind() {
    final List<Runnable> pending = new ArrayList<>(pendingAfterBind);
    pendingAfterBind.clear();
    for (Runnable runnable : pending) {
      mainHandler.post(runnable);
    }
  }

  private void initialize(GeolocatorLocationService service) {
    Log.d(TAG, "Initializing Geolocator services");
    foregroundLocationService = service;
    foregroundLocationService.setGeolocationManager(geolocationManager);
    foregroundLocationService.flutterEngineConnected();

    if (pluginBinding != null) {
      foregroundLocationService.setActivity(pluginBinding.getActivity());
    }

    if (streamHandler != null) {
      streamHandler.setForegroundLocationService(service);
    }
  }

  private void dispose() {
    Log.d(TAG, "Disposing Geolocator services");
    pendingAfterBind.clear();
    if (methodCallHandler != null) {
      methodCallHandler.stopListening();
      methodCallHandler.setActivity(null);
      methodCallHandler = null;
    }
    if (streamHandler != null) {
      streamHandler.stopListening();
      streamHandler.setForegroundServiceBinder(null);
      streamHandler.setForegroundLocationService(null);
      streamHandler = null;
    }
    if (locationServiceHandler != null) {
      locationServiceHandler.setContext(null);
      locationServiceHandler.stopListening();
      locationServiceHandler = null;
    }
    if (foregroundLocationService != null) {
      foregroundLocationService.setActivity(null);
    }
  }
}
