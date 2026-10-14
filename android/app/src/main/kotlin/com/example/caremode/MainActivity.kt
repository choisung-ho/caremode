package com.example.caremode

import android.content.Context
import android.media.AudioManager
import android.media.AudioFocusRequest
import android.media.MediaPlayer
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.os.Bundle

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.caremode/audio"
    private var audioManager: AudioManager? = null
    private var audioFocusRequest: AudioFocusRequest? = null
    private var silentMediaPlayer: MediaPlayer? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // AudioManager 초기화
        audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        
        // 🔥 실제 기기에서 물리적 버튼 작동하도록 강제 설정
        audioManager?.mode = AudioManager.MODE_IN_COMMUNICATION
        
        // 음량 버튼이 미디어 볼륨을 조절하도록 설정
        volumeControlStream = AudioManager.STREAM_MUSIC
        
        // 오디오 포커스 요청 (물리적 버튼 제어권 확보)
        requestAudioFocus()
        
        // 무음 미디어 세션 생성 (선택사항, 더 확실하게)
        createSilentMediaSession()
    }
    
    private fun createSilentMediaSession() {
        try {
            // 1초짜리 무음 오디오를 무한 반복 재생 (극히 작은 배터리 소모)
            silentMediaPlayer = MediaPlayer().apply {
                setAudioStreamType(AudioManager.STREAM_MUSIC)
                setVolume(0f, 0f) // 완전 무음
                isLooping = true
                
                // assets/raw/silence.mp3 파일 필요 (1초짜리 무음 파일)
                // 파일 없으면 무시하고 계속 진행
                try {
                    val afd = context.assets.openFd("raw/silence.mp3")
                    setDataSource(afd.fileDescriptor, afd.startOffset, afd.length)
                    afd.close()
                    prepare()
                    start()
                } catch (e: Exception) {
                    // 무음 파일 없으면 그냥 스킵 (없어도 AudioFocus만으로 작동할 수 있음)
                    android.util.Log.w("MainActivity", "무음 파일 없음 (선택사항): ${e.message}")
                }
            }
        } catch (e: Exception) {
            android.util.Log.e("MainActivity", "미디어 세션 생성 실패: ${e.message}")
        }
    }
    
    private fun requestAudioFocus() {
        audioManager?.let { manager ->
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                // Android 8.0 이상
                audioFocusRequest = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
                    .setAudioAttributes(
                        android.media.AudioAttributes.Builder()
                            .setUsage(android.media.AudioAttributes.USAGE_MEDIA)
                            .setContentType(android.media.AudioAttributes.CONTENT_TYPE_SPEECH)
                            .build()
                    )
                    .build()
                audioFocusRequest?.let { manager.requestAudioFocus(it) }
            } else {
                // Android 8.0 미만
                @Suppress("DEPRECATION")
                manager.requestAudioFocus(
                    null,
                    AudioManager.STREAM_MUSIC,
                    AudioManager.AUDIOFOCUS_GAIN
                )
            }
        }
    }
    
    private fun abandonAudioFocus() {
        audioManager?.let { manager ->
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                audioFocusRequest?.let { manager.abandonAudioFocusRequest(it) }
            } else {
                @Suppress("DEPRECATION")
                manager.abandonAudioFocus(null)
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "setVolume" -> {
                    val volume = call.argument<Double>("volume")
                    if (volume != null) {
                        setMediaVolume(volume)
                        result.success(null)
                    } else {
                        result.error("INVALID_ARGUMENT", "Volume must be provided", null)
                    }
                }
                "getVolume" -> {
                    val volume = getMediaVolume()
                    result.success(volume)
                }
                "getMaxVolume" -> {
                    val maxVolume = audioManager?.getStreamMaxVolume(AudioManager.STREAM_MUSIC) ?: 15
                    result.success(maxVolume)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    private fun setMediaVolume(volume: Double) {
        val maxVolume = audioManager?.getStreamMaxVolume(AudioManager.STREAM_MUSIC) ?: 15
        val targetVolume = (volume * maxVolume).toInt().coerceIn(0, maxVolume)
        audioManager?.setStreamVolume(AudioManager.STREAM_MUSIC, targetVolume, 0)
    }

    private fun getMediaVolume(): Double {
        val currentVolume = audioManager?.getStreamVolume(AudioManager.STREAM_MUSIC) ?: 0
        val maxVolume = audioManager?.getStreamMaxVolume(AudioManager.STREAM_MUSIC) ?: 15
        return currentVolume.toDouble() / maxVolume.toDouble()
    }

    override fun onResume() {
        super.onResume()
        // 앱이 포그라운드로 올 때마다 강제 설정
        audioManager?.mode = AudioManager.MODE_IN_COMMUNICATION
        volumeControlStream = AudioManager.STREAM_MUSIC
        requestAudioFocus()
    }

    override fun onPause() {
        super.onPause()
        // 백그라운드로 가도 미디어 세션 유지 (음량 버튼 계속 작동)
        // abandonAudioFocus() 주석 처리
    }
    
    override fun onDestroy() {
        super.onDestroy()
        // 앱 종료 시 정리
        audioManager?.mode = AudioManager.MODE_NORMAL
        silentMediaPlayer?.release()
        silentMediaPlayer = null
        abandonAudioFocus()
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) {
            // 포커스를 받을 때 음량 스트림 강제 설정 + 오디오 포커스 재획득
            volumeControlStream = AudioManager.STREAM_MUSIC
            requestAudioFocus()
        }
    }
}
