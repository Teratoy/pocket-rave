package org.pocketrave.bgmusic;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.Intent;
import android.content.pm.ServiceInfo;
import android.media.AudioAttributes;
import android.media.AudioFocusRequest;
import android.media.AudioManager;
import android.os.Build;
import android.os.IBinder;
import android.os.PowerManager;
import android.util.Log;

import java.io.File;

/**
 * Foreground media service that plays one DJ set: each track once, in
 * order, then stops itself. Runs on its own TrackPlayer so it is not
 * paused with the game when the app leaves the foreground. Plays at the
 * game's volume, crushed while the game's low-bit sound is on.
 */
public class MusicService extends Service {

    static final String ACTION_PLAY = "org.pocketrave.bgmusic.PLAY";
    static final String ACTION_PAUSE = "org.pocketrave.bgmusic.PAUSE";
    static final String ACTION_RESUME = "org.pocketrave.bgmusic.RESUME";
    static final String ACTION_STOP = "org.pocketrave.bgmusic.STOP";
    static final String EXTRA_TITLE = "title";
    static final String EXTRA_PATHS = "paths";

    private static final String TAG = "BackgroundMusic";
    private static final String CHANNEL_ID = "music";
    private static final int NOTIFICATION_ID = 1;
    private static final float DUCK_VOLUME = 0.2f;

    // Read by the plugin from the Godot thread.
    static volatile boolean running = false;
    static volatile int trackIndex = -1;
    static volatile boolean finished = false;
    /** The prepared player of the track playing, for its position. */
    static volatile TrackPlayer current;
    /** Set by the game: the music's gain, and whether it is crushed (see TrackPlayer). */
    static volatile float volume = 1f;
    static volatile boolean lowBit = false;
    /** Turned down while another app talks over the music. */
    private static volatile boolean ducked = false;

    private String title = "";
    private String[] paths = new String[0];
    private TrackPlayer player;
    private final AudioAttributes attributes = new AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_MEDIA)
            .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
            .build();
    /** Keeps the CPU decoding while the screen is off. */
    private PowerManager.WakeLock wakeLock;
    /** Paused by the game's pause button. */
    private boolean userPaused = false;
    /** Paused because another app took audio focus. */
    private boolean focusPaused = false;
    private AudioManager audio;
    private AudioFocusRequest focusRequest;
    /** Latest start request, so stopping never drops a newer play. */
    private int lastStartId;

    private final AudioManager.OnAudioFocusChangeListener focusListener = change -> {
        if (player == null) {
            return;
        }
        switch (change) {
            case AudioManager.AUDIOFOCUS_GAIN:
                ducked = false;
                applyVolume();
                if (focusPaused && !userPaused) {
                    player.start();
                }
                focusPaused = false;
                break;
            case AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK:
                ducked = true;
                applyVolume();
                break;
            case AudioManager.AUDIOFOCUS_LOSS:
            case AudioManager.AUDIOFOCUS_LOSS_TRANSIENT:
                if (player.isPlaying()) {
                    player.pause();
                    focusPaused = true;
                }
                break;
        }
        updateWakeLock();
    };

    /** Plays the current track at the game's volume, ducked if need be. */
    static void applyVolume() {
        TrackPlayer p = current;
        if (p != null) {
            p.setVolume(ducked ? volume * DUCK_VOLUME : volume);
        }
    }

    @Override
    public void onCreate() {
        super.onCreate();
        running = true;
        audio = (AudioManager) getSystemService(AUDIO_SERVICE);
        wakeLock = ((PowerManager) getSystemService(POWER_SERVICE))
                .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "PocketRave:music");
        wakeLock.setReferenceCounted(false);
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        lastStartId = startId;
        String action = intent != null ? intent.getAction() : null;
        if (ACTION_PLAY.equals(action)) {
            title = intent.getStringExtra(EXTRA_TITLE);
            String[] p = intent.getStringArrayExtra(EXTRA_PATHS);
            paths = p != null ? p : new String[0];
            userPaused = false;
            startInForeground();
            requestFocus();
            playTrack(0);
        } else if (ACTION_PAUSE.equals(action)) {
            userPaused = true;
            if (player != null && player.isPlaying()) {
                player.pause();
            }
            updateWakeLock();
        } else if (ACTION_RESUME.equals(action)) {
            userPaused = false;
            if (player != null && !player.isPlaying() && !focusPaused) {
                player.start();
            }
            updateWakeLock();
        } else {
            // Stop, or restarted by the system with no set to play.
            endSet(false);
        }
        return START_NOT_STICKY;
    }

    @Override
    public void onDestroy() {
        releasePlayer();
        abandonFocus();
        wakeLock.release();
        running = false;
        trackIndex = -1;
        super.onDestroy();
    }

    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }

    private void playTrack(int index) {
        releasePlayer();
        if (index >= paths.length) {
            endSet(true);
            return;
        }
        trackIndex = index;
        TrackPlayer tp = new TrackPlayer(attributes, (p, failed) -> {
            // A track ended after being replaced is old news.
            if (p != player) {
                return;
            }
            if (failed) {
                Log.w(TAG, "Error playing " + paths[index]);
            }
            playTrack(index + 1);
        });
        try {
            tp.prepare(paths[index]);
        } catch (Exception e) {
            Log.w(TAG, "Cannot play " + paths[index], e);
            tp.release();
            playTrack(index + 1);
            return;
        }
        player = tp;
        current = tp;
        applyVolume();
        if (!userPaused && !focusPaused) {
            tp.start();
        }
        updateWakeLock();
        updateNotification();
    }

    private void endSet(boolean completed) {
        releasePlayer();
        updateWakeLock();
        trackIndex = -1;
        if (completed) {
            finished = true;
        }
        abandonFocus();
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE);
        } else {
            stopForeground(true);
        }
        stopSelf(lastStartId);
    }

    private void releasePlayer() {
        if (player != null) {
            current = null;
            player.release();
            player = null;
        }
    }

    private void updateWakeLock() {
        if (player != null && player.isPlaying()) {
            wakeLock.acquire();
        } else {
            wakeLock.release();
        }
    }

    private void requestFocus() {
        focusPaused = false;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            if (focusRequest == null) {
                focusRequest = new AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
                        .setAudioAttributes(new AudioAttributes.Builder()
                                .setUsage(AudioAttributes.USAGE_MEDIA)
                                .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                                .build())
                        .setOnAudioFocusChangeListener(focusListener)
                        .build();
            }
            audio.requestAudioFocus(focusRequest);
        } else {
            audio.requestAudioFocus(focusListener, AudioManager.STREAM_MUSIC, AudioManager.AUDIOFOCUS_GAIN);
        }
    }

    private void abandonFocus() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            if (focusRequest != null) {
                audio.abandonAudioFocusRequest(focusRequest);
            }
        } else {
            audio.abandonAudioFocus(focusListener);
        }
    }

    private void startInForeground() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            NotificationChannel channel = new NotificationChannel(
                    CHANNEL_ID, "Music", NotificationManager.IMPORTANCE_LOW);
            getSystemService(NotificationManager.class).createNotificationChannel(channel);
        }
        Notification notification = buildNotification();
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(NOTIFICATION_ID, notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK);
        } else {
            startForeground(NOTIFICATION_ID, notification);
        }
    }

    private void updateNotification() {
        getSystemService(NotificationManager.class).notify(NOTIFICATION_ID, buildNotification());
    }

    private Notification buildNotification() {
        Notification.Builder b = Build.VERSION.SDK_INT >= Build.VERSION_CODES.O
                ? new Notification.Builder(this, CHANNEL_ID)
                : new Notification.Builder(this);
        b.setSmallIcon(getApplicationInfo().icon)
                .setContentTitle(title)
                .setOngoing(true)
                .setShowWhen(false);
        if (trackIndex >= 0 && trackIndex < paths.length) {
            String name = new File(paths[trackIndex]).getName();
            int dot = name.lastIndexOf('.');
            b.setContentText(dot > 0 ? name.substring(0, dot) : name);
        }
        Intent launch = getPackageManager().getLaunchIntentForPackage(getPackageName());
        if (launch != null) {
            b.setContentIntent(PendingIntent.getActivity(this, 0, launch,
                    PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT));
        }
        return b.build();
    }
}
