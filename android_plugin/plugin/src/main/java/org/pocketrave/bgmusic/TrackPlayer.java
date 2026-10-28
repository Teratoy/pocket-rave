package org.pocketrave.bgmusic;

import android.media.AudioAttributes;
import android.media.AudioFormat;
import android.media.AudioTrack;
import android.media.MediaCodec;
import android.media.MediaExtractor;
import android.media.MediaFormat;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;

import java.io.IOException;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.FloatBuffer;
import java.nio.ShortBuffer;

/**
 * Plays one audio file once. Decodes it on its own thread and writes the
 * samples to an AudioTrack, so they can be crushed on the way out while
 * MusicService.lowBit is on (see crush). MediaPlayer can't do that: it
 * never hands over the samples.
 */
final class TrackPlayer {

    /** Told on the main thread once the track has played out, or failed. */
    interface Listener {
        void onEnd(TrackPlayer player, boolean failed);
    }

    /** Crushed sound: bits per sample, and samples a second. Matches the game's (see sound_settings.gd). */
    private static final int CRUSH_BITS = 4;
    private static final float CRUSH_RATE = 5000f;
    private static final long TIMEOUT_US = 10_000;
    private static final long WAIT_MS = 10;
    /** A track still not moving after this long while playing won't; its end is skipped. */
    private static final long STALL_MS = 1000;
    private static final String TAG = "BackgroundMusic";

    private final AudioAttributes attributes;
    private final Listener listener;
    private final Handler main = new Handler(Looper.getMainLooper());
    private final MediaExtractor extractor = new MediaExtractor();
    private MediaCodec codec;
    private Thread thread;
    private volatile boolean released = false;

    // The AudioTrack and what it was made for; guarded by this, as the
    // decoding thread makes it while the service and game drive it.
    private AudioTrack track;
    private int rate;
    private int channels;
    private boolean floatOut;
    private boolean playing = false;
    private float volume = 1f;
    /** Frames played by AudioTracks this one replaced (on a format change). */
    private long framesBefore = 0;

    /** The crushed frame held until the next is due, and how far along to it (a next one is due at 1). */
    private float[] held = new float[0];
    private float phase = 1f;

    TrackPlayer(AudioAttributes attributes, Listener listener) {
        this.attributes = attributes;
        this.listener = listener;
    }

    /** Opens the file and starts decoding it; nothing is heard until start(). */
    void prepare(String path) throws IOException {
        extractor.setDataSource(path);
        MediaFormat format = null;
        for (int i = 0; i < extractor.getTrackCount(); i++) {
            MediaFormat f = extractor.getTrackFormat(i);
            String mime = f.getString(MediaFormat.KEY_MIME);
            if (mime != null && mime.startsWith("audio/")) {
                extractor.selectTrack(i);
                format = f;
                break;
            }
        }
        if (format == null) {
            throw new IOException("No audio in " + path);
        }
        codec = MediaCodec.createDecoderByType(format.getString(MediaFormat.KEY_MIME));
        codec.configure(format, null, null, 0);
        codec.start();
        // Some decoders only say what they put out once they do.
        MediaFormat out = codec.getOutputFormat();
        boolean known = out.containsKey(MediaFormat.KEY_SAMPLE_RATE)
                && out.containsKey(MediaFormat.KEY_CHANNEL_COUNT);
        setFormat(known ? out : format);
        thread = new Thread(this::decode, "TrackPlayer");
        thread.start();
    }

    synchronized void start() {
        playing = true;
        if (track != null) {
            track.play();
        }
    }

    synchronized void pause() {
        playing = false;
        if (track != null) {
            track.pause();
        }
    }

    synchronized boolean isPlaying() {
        return playing;
    }

    synchronized void setVolume(float v) {
        volume = v;
        if (track != null) {
            track.setVolume(v);
        }
    }

    /** Seconds into the track. */
    synchronized double getPosition() {
        long frames = framesBefore + (track != null ? playedFrames() : 0);
        return rate > 0 ? (double) frames / rate : 0;
    }

    /** Stops for good; the listener isn't told. */
    void release() {
        released = true;
        if (thread != null) {
            thread.interrupt();
            try {
                thread.join(1000);
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
            }
        }
        if (codec != null) {
            try {
                codec.stop();
            } catch (IllegalStateException e) {
                // Never started, or already broken.
            }
            codec.release();
        }
        extractor.release();
        synchronized (this) {
            if (track != null) {
                track.release();
                track = null;
            }
        }
    }

    private void decode() {
        boolean failed = false;
        try {
            MediaCodec.BufferInfo info = new MediaCodec.BufferInfo();
            float[] samples = new float[0];
            boolean inputDone = false;
            long written = 0;
            while (!released) {
                if (!inputDone) {
                    int in = codec.dequeueInputBuffer(TIMEOUT_US);
                    if (in >= 0) {
                        int size = extractor.readSampleData(codec.getInputBuffer(in), 0);
                        if (size < 0) {
                            codec.queueInputBuffer(in, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM);
                            inputDone = true;
                        } else {
                            codec.queueInputBuffer(in, 0, size, extractor.getSampleTime(), 0);
                            extractor.advance();
                        }
                    }
                }
                int out = codec.dequeueOutputBuffer(info, TIMEOUT_US);
                if (out == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                    if (setFormat(codec.getOutputFormat())) {
                        written = 0;
                    }
                    continue;
                }
                if (out < 0) {
                    continue;
                }
                ByteBuffer bytes = codec.getOutputBuffer(out);
                bytes.position(info.offset).limit(info.offset + info.size);
                int n;
                if (floatOut) {
                    FloatBuffer f = bytes.slice().order(ByteOrder.nativeOrder()).asFloatBuffer();
                    n = f.remaining();
                    samples = fit(samples, n);
                    f.get(samples, 0, n);
                } else {
                    ShortBuffer s = bytes.slice().order(ByteOrder.nativeOrder()).asShortBuffer();
                    n = s.remaining();
                    samples = fit(samples, n);
                    for (int i = 0; i < n; i++) {
                        samples[i] = s.get(i) / 32768f;
                    }
                }
                boolean end = (info.flags & MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0;
                codec.releaseOutputBuffer(out, false);
                if (MusicService.lowBit) {
                    crush(samples, n);
                }
                write(samples, n);
                written += n / channels;
                if (end) {
                    break;
                }
            }
            playOut(written);
        } catch (InterruptedException e) {
            // Released.
        } catch (Exception e) {
            Log.w(TAG, "Playback failed", e);
            failed = true;
        }
        if (!released) {
            boolean f = failed;
            main.post(() -> listener.onEnd(this, f));
        }
    }

    /** Makes the AudioTrack for the decoder's output, unless the one there fits. True if it made one. */
    private synchronized boolean setFormat(MediaFormat format) {
        int r = format.getInteger(MediaFormat.KEY_SAMPLE_RATE);
        int c = format.getInteger(MediaFormat.KEY_CHANNEL_COUNT);
        boolean f = format.containsKey(MediaFormat.KEY_PCM_ENCODING)
                && format.getInteger(MediaFormat.KEY_PCM_ENCODING) == AudioFormat.ENCODING_PCM_FLOAT;
        if (track != null && r == rate && c == channels && f == floatOut) {
            return false;
        }
        if (c != 1 && c != 2) {
            throw new IllegalStateException(c + " channels");
        }
        if (track != null) {
            framesBefore += playedFrames();
            track.release();
        }
        rate = r;
        channels = c;
        floatOut = f;
        held = new float[c];
        int mask = c == 1 ? AudioFormat.CHANNEL_OUT_MONO : AudioFormat.CHANNEL_OUT_STEREO;
        int min = AudioTrack.getMinBufferSize(r, mask, AudioFormat.ENCODING_PCM_FLOAT);
        track = new AudioTrack.Builder()
                .setAudioAttributes(attributes)
                .setAudioFormat(new AudioFormat.Builder()
                        .setEncoding(AudioFormat.ENCODING_PCM_FLOAT)
                        .setSampleRate(r)
                        .setChannelMask(mask)
                        .build())
                .setBufferSizeInBytes(min * 2)
                .setTransferMode(AudioTrack.MODE_STREAM)
                .build();
        track.setVolume(volume);
        if (playing) {
            track.play();
        }
        return true;
    }

    /** Writes n samples, waiting for room (and through pauses) as needed. */
    private void write(float[] samples, int n) throws InterruptedException {
        int done = 0;
        while (done < n && !released) {
            int w;
            synchronized (this) {
                w = track.write(samples, done, n - done, AudioTrack.WRITE_NON_BLOCKING);
            }
            if (w < 0) {
                throw new IllegalStateException("AudioTrack write error " + w);
            }
            done += w;
            if (done < n) {
                Thread.sleep(WAIT_MS);
            }
        }
    }

    /** Waits for the frames written to the current AudioTrack to be heard. */
    private void playOut(long written) throws InterruptedException {
        long last = -1;
        long stalled = 0;
        while (!released) {
            synchronized (this) {
                long played = playedFrames();
                if (played >= written) {
                    return;
                }
                // Too little left to fill the AudioTrack may never start it.
                stalled = played == last && playing ? stalled + WAIT_MS : 0;
                if (stalled >= STALL_MS) {
                    return;
                }
                last = played;
            }
            Thread.sleep(WAIT_MS);
        }
    }

    // The head position counts frames as an unsigned 32 bit int.
    private long playedFrames() {
        return track.getPlaybackHeadPosition() & 0xFFFFFFFFL;
    }

    /** Holds each frame until the next one at CRUSH_RATE is due, rounded to CRUSH_BITS. */
    private void crush(float[] samples, int n) {
        float step = CRUSH_RATE / rate;
        float levels = 1 << (CRUSH_BITS - 1);
        for (int i = 0; i < n; i += channels) {
            phase += step;
            if (phase >= 1f) {
                phase -= 1f;
                for (int c = 0; c < channels; c++) {
                    held[c] = Math.round(samples[i + c] * levels) / levels;
                }
            }
            for (int c = 0; c < channels; c++) {
                samples[i + c] = held[c];
            }
        }
    }

    private static float[] fit(float[] buf, int n) {
        return buf.length >= n ? buf : new float[n];
    }
}
