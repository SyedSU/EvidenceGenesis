class_name GenesisAudio
extends RefCounted

static func create() -> AudioStreamWAV:
	# Original synthesized ambience. No downloaded music or audio assets.
	var rate=16000;var seconds=12;var bytes=PackedByteArray();bytes.resize(rate*seconds*2)
	var notes=[164.81,196.0,246.94,293.66,329.63,392.0]
	for i in rate*seconds:
		var t=float(i)/rate
		var value=.012*(sin(TAU*164.81*t)+sin(TAU*246.94*t))
		var n=int(t/2);var dt=t-n*2
		value+=.065*exp(-dt*2)*(sin(TAU*notes[n]*dt)+.2*sin(TAU*notes[n]*2*dt))
		value*=minf(1.0,minf(t/.2,(seconds-t)/.2))
		bytes.encode_s16(i*2,int(clampf(value,-1,1)*32767))
	var stream=AudioStreamWAV.new();stream.format=AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate=rate;stream.data=bytes;stream.loop_mode=AudioStreamWAV.LOOP_FORWARD;stream.loop_end=rate*seconds
	return stream
