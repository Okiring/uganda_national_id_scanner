package com.uganda.scanner;

import android.app.Activity;
import android.content.Intent;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.embedding.engine.plugins.activity.ActivityAware;
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.PluginRegistry;

/**
 * Flutter plugin entry point. Launches {@link NationalIdScannerActivity} and
 * returns the raw PDF417 barcode text to Dart.
 */
public class NationalIdScannerPlugin
        implements FlutterPlugin,
                MethodChannel.MethodCallHandler,
                ActivityAware,
                PluginRegistry.ActivityResultListener {

    private static final String CHANNEL = "com.uganda.scanner/national_id_scanner";
    private static final int SCANNER_REQUEST_CODE = 5402;

    private MethodChannel channel;
    @Nullable private Activity activity;
    @Nullable private ActivityPluginBinding activityBinding;
    @Nullable private MethodChannel.Result pendingResult;

    @Override
    public void onAttachedToEngine(@NonNull FlutterPluginBinding binding) {
        channel = new MethodChannel(binding.getBinaryMessenger(), CHANNEL);
        channel.setMethodCallHandler(this);
    }

    @Override
    public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
        if (channel != null) {
            channel.setMethodCallHandler(null);
            channel = null;
        }
    }

    @Override
    public void onMethodCall(@NonNull MethodCall call, @NonNull MethodChannel.Result result) {
        if (!"scan".equals(call.method)) {
            result.notImplemented();
            return;
        }

        if (activity == null) {
            result.error("NO_ACTIVITY", "Scanner requires an active Android activity.", null);
            return;
        }

        if (pendingResult != null) {
            result.error("SCAN_IN_PROGRESS", "A national ID scan is already in progress.", null);
            return;
        }

        pendingResult = result;
        activity.startActivityForResult(
                new Intent(activity, NationalIdScannerActivity.class),
                SCANNER_REQUEST_CODE);
    }

    @Override
    public boolean onActivityResult(int requestCode, int resultCode, @Nullable Intent data) {
        if (requestCode != SCANNER_REQUEST_CODE || pendingResult == null) {
            return false;
        }

        MethodChannel.Result result = pendingResult;
        pendingResult = null;

        if (resultCode == Activity.RESULT_OK && data != null) {
            result.success(data.getStringExtra(NationalIdScannerActivity.EXTRA_RAW_VALUE));
        } else {
            result.success(null);
        }
        return true;
    }

    @Override
    public void onAttachedToActivity(@NonNull ActivityPluginBinding binding) {
        activity = binding.getActivity();
        activityBinding = binding;
        binding.addActivityResultListener(this);
    }

    @Override
    public void onDetachedFromActivityForConfigChanges() {
        detachActivity();
    }

    @Override
    public void onReattachedToActivityForConfigChanges(@NonNull ActivityPluginBinding binding) {
        onAttachedToActivity(binding);
    }

    @Override
    public void onDetachedFromActivity() {
        detachActivity();
    }

    private void detachActivity() {
        if (activityBinding != null) {
            activityBinding.removeActivityResultListener(this);
            activityBinding = null;
        }
        activity = null;
    }
}
