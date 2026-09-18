package com.uganda.scanner;

import android.Manifest;
import android.app.Activity;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Matrix;
import android.graphics.Paint;
import android.graphics.Rect;
import android.graphics.RectF;
import android.os.Bundle;
import android.os.SystemClock;
import android.util.Log;
import android.view.Gravity;
import android.view.MotionEvent;
import android.view.View;
import android.widget.Button;
import android.widget.FrameLayout;
import android.widget.TextView;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.appcompat.app.AppCompatActivity;
import androidx.camera.core.Camera;
import androidx.camera.core.CameraSelector;
import androidx.camera.core.FocusMeteringAction;
import androidx.camera.core.ImageAnalysis;
import androidx.camera.core.ImageProxy;
import androidx.camera.core.Preview;
import androidx.camera.core.TorchState;
import androidx.camera.core.resolutionselector.AspectRatioStrategy;
import androidx.camera.core.resolutionselector.ResolutionSelector;
import androidx.camera.core.resolutionselector.ResolutionStrategy;
import androidx.camera.lifecycle.ProcessCameraProvider;
import androidx.camera.view.PreviewView;
import androidx.core.app.ActivityCompat;
import androidx.core.content.ContextCompat;

import com.google.common.util.concurrent.ListenableFuture;

import java.util.HashSet;
import java.util.List;
import java.util.Set;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

import zxingcpp.BarcodeReader;

/**
 * Native CameraX + ZXing-C++ PDF417 scanner for Ugandan National ID barcodes.
 */
public class NationalIdScannerActivity extends AppCompatActivity {
    public static final String EXTRA_RAW_VALUE = "national_id_barcode_raw_value";

    private static final int CAMERA_PERMISSION_REQUEST = 5401;
    private static final String TAG = "NationalIdScanner";

    private PreviewView previewView;
    private BarcodeGuideView guideView;
    private TextView statusView;
    private ExecutorService analyzerExecutor;

    @Nullable private ProcessCameraProvider cameraProvider;
    @Nullable private Camera camera;

    private boolean useLocalAverage = false;
    private int failedFrames = 0;
    private volatile boolean decoding = true;

    private final BarcodeReader reader = createReader();

    private static BarcodeReader createReader() {
        BarcodeReader barcodeReader = new BarcodeReader();
        BarcodeReader.Options options = barcodeReader.getOptions();
        Set<BarcodeReader.Format> formats = new HashSet<>();
        formats.add(BarcodeReader.Format.PDF_417);
        options.setFormats(formats);
        options.setTryHarder(false);
        options.setTryRotate(true);
        options.setTryInvert(true);
        options.setTryDownscale(true);
        options.setMaxNumberOfSymbols(1);
        options.setBinarizer(BarcodeReader.Binarizer.LOCAL_AVERAGE);
        options.setTextMode(BarcodeReader.TextMode.PLAIN);
        return barcodeReader;
    }

    @Override
    protected void onCreate(@Nullable Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        getWindow().setStatusBarColor(Color.BLACK);
        getWindow().setNavigationBarColor(Color.BLACK);
        analyzerExecutor = Executors.newSingleThreadExecutor();
        setContentView(buildContentView());

        if (ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA)
                == PackageManager.PERMISSION_GRANTED) {
            startCamera();
        } else {
            ActivityCompat.requestPermissions(
                    this,
                    new String[] {Manifest.permission.CAMERA},
                    CAMERA_PERMISSION_REQUEST);
        }
    }

    private View buildContentView() {
        FrameLayout root = new FrameLayout(this);
        root.setBackgroundColor(Color.BLACK);

        previewView = new PreviewView(this);
        previewView.setScaleType(PreviewView.ScaleType.FILL_CENTER);
        previewView.setImplementationMode(PreviewView.ImplementationMode.PERFORMANCE);
        previewView.setOnTouchListener(
                (v, event) -> {
                    if (event.getAction() == MotionEvent.ACTION_UP) {
                        focusAt(event.getX(), event.getY());
                    }
                    return true;
                });
        root.addView(
                previewView,
                new FrameLayout.LayoutParams(
                        FrameLayout.LayoutParams.MATCH_PARENT,
                        FrameLayout.LayoutParams.MATCH_PARENT));

        guideView = new BarcodeGuideView(this);
        root.addView(
                guideView,
                new FrameLayout.LayoutParams(
                        FrameLayout.LayoutParams.MATCH_PARENT,
                        FrameLayout.LayoutParams.MATCH_PARENT));

        statusView = new TextView(this);
        statusView.setText("Hold the barcode inside the frame");
        statusView.setTextColor(Color.WHITE);
        statusView.setTextSize(16f);
        statusView.setGravity(Gravity.CENTER);
        statusView.setBackgroundColor(0xB3000000);
        statusView.setPadding(dp(16), dp(10), dp(16), dp(10));
        FrameLayout.LayoutParams statusParams =
                new FrameLayout.LayoutParams(
                        FrameLayout.LayoutParams.WRAP_CONTENT,
                        FrameLayout.LayoutParams.WRAP_CONTENT,
                        Gravity.TOP | Gravity.CENTER_HORIZONTAL);
        statusParams.topMargin = dp(24);
        statusParams.setMarginStart(dp(20));
        statusParams.setMarginEnd(dp(20));
        root.addView(statusView, statusParams);

        Button closeButton = new Button(this);
        closeButton.setText("Close");
        closeButton.setOnClickListener(
                v -> {
                    setResult(Activity.RESULT_CANCELED);
                    finish();
                });
        FrameLayout.LayoutParams closeParams =
                new FrameLayout.LayoutParams(
                        FrameLayout.LayoutParams.WRAP_CONTENT, dp(52), Gravity.BOTTOM | Gravity.START);
        closeParams.bottomMargin = dp(24);
        closeParams.setMarginStart(dp(20));
        root.addView(closeButton, closeParams);

        Button flashButton = new Button(this);
        flashButton.setText("Flash");
        flashButton.setOnClickListener(v -> toggleFlash());
        FrameLayout.LayoutParams flashParams =
                new FrameLayout.LayoutParams(
                        FrameLayout.LayoutParams.WRAP_CONTENT, dp(52), Gravity.BOTTOM | Gravity.END);
        flashParams.bottomMargin = dp(24);
        flashParams.setMarginEnd(dp(20));
        root.addView(flashButton, flashParams);

        return root;
    }

    private void startCamera() {
        ListenableFuture<ProcessCameraProvider> providerFuture =
                ProcessCameraProvider.getInstance(this);
        providerFuture.addListener(
                () -> {
                    if (isDestroyed()) {
                        return;
                    }

                    ProcessCameraProvider provider;
                    try {
                        provider = providerFuture.get();
                    } catch (Exception error) {
                        showCameraError(error);
                        return;
                    }

                    ResolutionSelector resolutionSelector =
                            new ResolutionSelector.Builder()
                                    .setResolutionStrategy(
                                            ResolutionStrategy.HIGHEST_AVAILABLE_STRATEGY)
                                    .setAspectRatioStrategy(
                                            AspectRatioStrategy.RATIO_16_9_FALLBACK_AUTO_STRATEGY)
                                    .setAllowedResolutionMode(
                                            ResolutionSelector
                                                    .PREFER_HIGHER_RESOLUTION_OVER_CAPTURE_RATE)
                                    .build();

                    Preview preview =
                            new Preview.Builder()
                                    .setResolutionSelector(resolutionSelector)
                                    .build();
                    preview.setSurfaceProvider(previewView.getSurfaceProvider());

                    ImageAnalysis analysis =
                            new ImageAnalysis.Builder()
                                    .setResolutionSelector(resolutionSelector)
                                    .setBackpressureStrategy(
                                            ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                                    .build();
                    analysis.setAnalyzer(analyzerExecutor, this::analyzeImage);

                    try {
                        provider.unbindAll();
                        camera =
                                provider.bindToLifecycle(
                                        this,
                                        CameraSelector.DEFAULT_BACK_CAMERA,
                                        preview,
                                        analysis);
                        cameraProvider = provider;
                    } catch (Exception error) {
                        showCameraError(error);
                    }
                },
                ContextCompat.getMainExecutor(this));
    }

    private void analyzeImage(@NonNull ImageProxy image) {
        try {
            if (!decoding) {
                return;
            }

            Rect frameRoi = mapGuideToFrame(image);
            if (frameRoi == null) {
                frameRoi = image.getCropRect();
            }
            image.setCropRect(frameRoi);

            useLocalAverage = !useLocalAverage;
            reader.getOptions()
                    .setBinarizer(
                            useLocalAverage
                                    ? BarcodeReader.Binarizer.LOCAL_AVERAGE
                                    : BarcodeReader.Binarizer.GLOBAL_HISTOGRAM);

            long startedAt = SystemClock.elapsedRealtime();
            List<BarcodeReader.Result> results = reader.read(image);
            BarcodeReader.Result match = null;
            for (BarcodeReader.Result candidate : results) {
                if (candidate.getFormat() == BarcodeReader.Format.PDF_417
                        && candidate.getText() != null
                        && !candidate.getText().isEmpty()) {
                    match = candidate;
                    break;
                }
            }
            long elapsed = SystemClock.elapsedRealtime() - startedAt;

            if (match == null) {
                failedFrames += 1;
                if (failedFrames % 30 == 0) {
                    Log.d(
                            TAG,
                            "No PDF417 after "
                                    + failedFrames
                                    + " frames; frame="
                                    + image.getWidth()
                                    + "x"
                                    + image.getHeight()
                                    + ", rotation="
                                    + image.getImageInfo().getRotationDegrees()
                                    + ", roi="
                                    + frameRoi
                                    + ", decode="
                                    + elapsed
                                    + "ms, binarizer="
                                    + reader.getOptions().getBinarizer());
                }
                return;
            }

            decoding = false;
            final String text = match.getText();
            Log.d(TAG, "PDF417 decoded in " + elapsed + "ms");
            Log.d(TAG, "PDF417 received text: " + text);
            runOnUiThread(
                    () -> {
                        Intent data = new Intent();
                        data.putExtra(EXTRA_RAW_VALUE, text);
                        setResult(Activity.RESULT_OK, data);
                        finish();
                    });
        } catch (Exception error) {
            Log.e(TAG, "Frame analysis failed", error);
        } finally {
            image.close();
        }
    }

    @Nullable
    private Rect mapGuideToFrame(@NonNull ImageProxy image) {
        int viewWidth = previewView.getWidth();
        int viewHeight = previewView.getHeight();
        if (viewWidth < 1 || viewHeight < 1) {
            return null;
        }

        int rotation = image.getImageInfo().getRotationDegrees();
        int uprightWidth = (rotation == 90 || rotation == 270) ? image.getHeight() : image.getWidth();
        int uprightHeight =
                (rotation == 90 || rotation == 270) ? image.getWidth() : image.getHeight();
        if (uprightWidth < 1 || uprightHeight < 1) {
            return null;
        }

        int coveredWidth = uprightWidth;
        int coveredHeight = uprightHeight;
        if ((long) viewWidth * coveredWidth < (long) viewHeight * coveredHeight) {
            coveredWidth = coveredWidth * viewHeight / coveredHeight;
            coveredHeight = viewHeight;
        } else {
            coveredHeight = coveredHeight * viewWidth / coveredWidth;
            coveredWidth = viewWidth;
        }

        Rect previewRect =
                new Rect(
                        (viewWidth - coveredWidth) / 2,
                        (viewHeight - coveredHeight) / 2,
                        (viewWidth + coveredWidth) / 2,
                        (viewHeight + coveredHeight) / 2);
        RectF viewRoi = guideView.guideRect();
        RectF mapped = new RectF();
        Matrix matrix = new Matrix();
        matrix.setTranslate(-previewRect.left, -previewRect.top);
        matrix.postScale(1f / previewRect.width(), 1f / previewRect.height());
        matrix.postRotate(-rotation, 0.5f, 0.5f);
        matrix.postScale(image.getWidth(), image.getHeight());
        matrix.mapRect(mapped, viewRoi);

        int left = clamp((int) Math.round(mapped.left), 0, image.getWidth());
        int top = clamp((int) Math.round(mapped.top), 0, image.getHeight());
        int right = clamp((int) Math.round(mapped.right), 0, image.getWidth());
        int bottom = clamp((int) Math.round(mapped.bottom), 0, image.getHeight());
        if (left < right && top < bottom) {
            return new Rect(left, top, right, bottom);
        }
        return null;
    }

    private void focusAt(float x, float y) {
        if (camera == null) {
            return;
        }
        camera.getCameraControl()
                .startFocusAndMetering(
                        new FocusMeteringAction.Builder(
                                        previewView.getMeteringPointFactory().createPoint(x, y))
                                .build());
    }

    private void toggleFlash() {
        if (camera == null || !camera.getCameraInfo().hasFlashUnit()) {
            return;
        }
        Integer torchState = camera.getCameraInfo().getTorchState().getValue();
        boolean turnOn = torchState == null || torchState != TorchState.ON;
        camera.getCameraControl().enableTorch(turnOn);
    }

    private void showCameraError(Exception error) {
        Log.e(TAG, "Could not start camera", error);
        statusView.setText("Could not start the camera. Check camera permission.");
    }

    @Override
    public void onRequestPermissionsResult(
            int requestCode, @NonNull String[] permissions, @NonNull int[] grantResults) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults);
        if (requestCode != CAMERA_PERMISSION_REQUEST) {
            return;
        }
        if (grantResults.length > 0 && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
            startCamera();
        } else {
            statusView.setText("Camera permission is required to scan the ID.");
        }
    }

    @Override
    protected void onDestroy() {
        decoding = false;
        if (cameraProvider != null) {
            cameraProvider.unbindAll();
        }
        if (analyzerExecutor != null) {
            analyzerExecutor.shutdown();
        }
        super.onDestroy();
    }

    private int dp(int value) {
        return Math.round(value * getResources().getDisplayMetrics().density);
    }

    private static int clamp(int value, int min, int max) {
        return Math.max(min, Math.min(max, value));
    }

    private static final class BarcodeGuideView extends View {
        private final Paint borderPaint = new Paint(Paint.ANTI_ALIAS_FLAG);

        BarcodeGuideView(android.content.Context context) {
            super(context);
            borderPaint.setColor(Color.WHITE);
            borderPaint.setStyle(Paint.Style.STROKE);
            borderPaint.setStrokeWidth(getResources().getDisplayMetrics().density * 3f);
        }

        RectF guideRect() {
            float guideWidth = getWidth() * 0.92f;
            float guideHeight = guideWidth / 2.8f;
            float maximumHeight = getHeight() * 0.55f;
            if (guideHeight > maximumHeight) {
                guideHeight = maximumHeight;
                guideWidth = guideHeight * 2.8f;
            }
            float left = (getWidth() - guideWidth) / 2f;
            float top = (getHeight() - guideHeight) / 2f;
            return new RectF(left, top, left + guideWidth, top + guideHeight);
        }

        @Override
        protected void onDraw(@NonNull Canvas canvas) {
            super.onDraw(canvas);
            float radius = getResources().getDisplayMetrics().density * 12f;
            canvas.drawRoundRect(guideRect(), radius, radius, borderPaint);
        }
    }
}
