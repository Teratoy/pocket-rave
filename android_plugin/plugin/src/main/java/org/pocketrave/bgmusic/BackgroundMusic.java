package org.pocketrave.bgmusic;

import android.app.Activity;
import android.content.Intent;
import android.os.Build;

import org.godotengine.godot.Godot;
import org.godotengine.godot.plugin.GodotPlugin;
import org.godotengine.godot.plugin.UsedByGodot;

/**
 * Godot singleton "BackgroundMusic". Plays a DJ set through MusicService,
 * which keeps going while the game is in the background or the screen is
 * off. The game polls getTrackIndex() and isFinished() to follow along.
 */
public class BackgroundMusic extends GodotPlugin {

    public BackgroundMusic(Godot godot) {
        super(godot);
    }

    @Override
    public String getPluginName() {
        return "BackgroundMusic";
    }

    /** Plays the tracks (absolute file paths) once each, in order. */
    @UsedByGodot
    public void playSet(String title, String[] paths) {
        Intent intent = command(MusicService.ACTION_PLAY);
        if (intent == null) {
            return;
        }
        intent.putExtra(MusicService.EXTRA_TITLE, title);
        intent.putExtra(MusicService.EXTRA_PATHS, paths);
        // Set now so a poll before the service starts sees the new set.
        MusicService.finished = false;
        MusicService.trackIndex = 0;
        Activity activity = getActivity();
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            activity.startForegroundService(intent);
        } else {
            activity.startService(intent);
        }
    }

    @UsedByGodot
    public void pause() {
        send(MusicService.ACTION_PAUSE);
    }

    @UsedByGodot
    public void resume() {
        send(MusicService.ACTION_RESUME);
    }

    @UsedByGodot
    public void stop() {
        send(MusicService.ACTION_STOP);
    }

    /** Index of the track playing, or -1 when no set is playing. */
    @UsedByGodot
    public int getTrackIndex() {
        return MusicService.trackIndex;
    }

    /** Seconds into the playing track, or 0 when none is playing. */
    @UsedByGodot
    public double getPosition() {
        TrackPlayer p = MusicService.current;
        return p != null ? p.getPosition() : 0;
    }

    /** Gain for the music, from 0 (silent) to 1; kept between sets. */
    @UsedByGodot
    public void setVolume(double gain) {
        MusicService.volume = (float) gain;
        MusicService.applyVolume();
    }

    /** Crushes the music to a few bits at a low sample rate (see TrackPlayer); kept between sets. */
    @UsedByGodot
    public void setLowBit(boolean on) {
        MusicService.lowBit = on;
    }

    /** True once the last track of the set has ended. */
    @UsedByGodot
    public boolean isFinished() {
        return MusicService.finished;
    }

    @Override
    public void onMainDestroy() {
        send(MusicService.ACTION_STOP);
        super.onMainDestroy();
    }

    private Intent command(String action) {
        Activity activity = getActivity();
        if (activity == null) {
            return null;
        }
        return new Intent(activity, MusicService.class).setAction(action);
    }

    // Commands other than play only matter while the service is running.
    private void send(String action) {
        if (!MusicService.running) {
            return;
        }
        Intent intent = command(action);
        if (intent != null) {
            getActivity().startService(intent);
        }
    }
}
