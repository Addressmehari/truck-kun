import os
import wave
import struct
import math

def save_wav(filename, data, sample_rate=44100):
    filepath = os.path.join("audio", filename)
    os.makedirs(os.path.dirname(filepath), exist_ok=True)
    with wave.open(filepath, 'wb') as wav_file:
        wav_file.setparams((1, 2, sample_rate, len(data), 'NONE', 'not compressed'))
        for sample in data:
            val = int(max(-32768, min(32767, sample * 32767)))
            wav_file.writeframes(struct.pack('<h', val))
    print(f"Generated {filepath} with {len(data)} samples (~{len(data)/sample_rate:.2f} seconds)")

def generate_soft_triangle_sine(freq, duration, sample_rate=44100, volume=1.0):
    num_samples = int(duration * sample_rate)
    samples = []
    for i in range(num_samples):
        t = i / sample_rate
        phase = 2.0 * math.pi * freq * t
        
        # Triangle wave
        norm_p = (phase % (2.0 * math.pi)) / (2.0 * math.pi)
        if norm_p < 0.25:
            tri = norm_p * 4.0
        elif norm_p < 0.75:
            tri = 2.0 - norm_p * 4.0
        else:
            tri = norm_p * 4.0 - 4.0
            
        # Sine wave (warm fundamental)
        sine = math.sin(phase)
        
        # Mix them: 60% triangle (for retro character), 40% sine (for smooth modern body)
        val = 0.6 * tri + 0.4 * sine
        
        # Tight exponential decay envelope
        env = math.exp(-t * 20.0)
        
        samples.append(val * env * volume)
    return samples

def apply_lowpass_filter(samples, window_size=5):
    """Applies a moving average filter to smooth out harsh high-frequency 'pixelation'."""
    out = []
    for i in range(len(samples)):
        val = 0.0
        count = 0
        for w in range(window_size):
            idx = i - w
            if idx >= 0:
                val += samples[idx]
                count += 1
        out.append(val / count if count > 0 else 0.0)
    return out

def make_coin_sound():
    sample_rate = 44100
    # Note 1: E5 (659.25 Hz) for 0.05 seconds
    n1 = generate_soft_triangle_sine(659.25, 0.05, sample_rate, volume=0.45)
    # Note 2: B5 (987.77 Hz) for 0.22 seconds
    n2 = generate_soft_triangle_sine(987.77, 0.22, sample_rate, volume=0.45)
    
    combined = n1 + n2
    # Apply moving average filter to soften the waveforms (removes raw aliasing buzz)
    filtered = apply_lowpass_filter(combined, window_size=5)
    
    # Simple delay reflection for spatial depth
    delay_samples = int(0.06 * sample_rate)
    decay = 0.25
    for i in range(delay_samples, len(filtered)):
        filtered[i] += filtered[i - delay_samples] * decay
        
    save_wav("sfx_coin.wav", filtered, sample_rate)

if __name__ == "__main__":
    make_coin_sound()
