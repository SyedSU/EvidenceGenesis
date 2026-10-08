class_name GenesisArt
extends Node2D

const ORIGIN=Vector2(640,62)
const TILE=Vector2(34,17)
const INK=Color("233e36")
var art_time=0.0

func iso(v: Vector2, height: float=0) -> Vector2:
	return ORIGIN+Vector2((v.x-v.y)*TILE.x,(v.x+v.y)*TILE.y-height)

func inverse(point: Vector2) -> Vector2:
	var p=point-ORIGIN
	return Vector2((p.x/TILE.x+p.y/TILE.y)/2.0,(p.y/TILE.y-p.x/TILE.x)/2.0)

func poly(points: Array, color: String):
	draw_colored_polygon(PackedVector2Array(points),Color(color))

func box(pos: Vector2, size: Vector2, height: float, top: String, front: String, side: String):
	var a=iso(pos,height); var b=iso(pos+Vector2(size.x,0),height)
	var e=iso(pos+size,height); var f=iso(pos+Vector2(0,size.y),height)
	poly([f,e,iso(pos+size),iso(pos+Vector2(0,size.y))],front)
	poly([b,e,iso(pos+size),iso(pos+Vector2(size.x,0))],side)
	poly([a,b,e,f],top)

func pixel(x: float, y: float, w: float, h: float, color: String):
	draw_rect(Rect2(roundf(x),roundf(y),w,h),Color(color))

func tree(pos: Vector2, variant: int=0):
	var p=iso(pos); var sway=roundf(sin(art_time*.8+pos.x)*1.5)
	oval(p+Vector2(0,6),Vector2(36,12),Color("143b382b"))
	pixel(p.x-6,p.y-58,12,61,"765745");pixel(p.x-3,p.y-53,4,57,"a47b51")
	pixel(p.x+4,p.y-32,13,5,"765745");pixel(p.x-17,p.y-41,15,5,"765745")
	var colors=["365746","486f4d","638c57","7b9d61","a1b772"]
	var patches=[Vector3(-21,-76,22),Vector3(14,-70,24),Vector3(-2,-98,30),Vector3(-26,-103,18),Vector3(20,-102,21),Vector3(-3,-119,22)]
	for i in patches.size():
		var t=patches[i]; var q=p+Vector2(t.x+sway,t.y)
		draw_circle(q,t.z,Color(colors[(i+variant)%3]));pixel(q.x-t.z+4,q.y-t.z+5,t.z*1.2,8,colors[3]);pixel(q.x-7,q.y-4,12,6,colors[4])
	if variant==1:
		for offset in [Vector2(-18,-92),Vector2(17,-109),Vector2(5,-73)]:
			pixel(p.x+offset.x,p.y+offset.y,6,6,"c98663");pixel(p.x+offset.x+1,p.y+offset.y,3,2,"e9b675")

func oval(pos: Vector2, radius: Vector2, color: Color):
	var points=PackedVector2Array()
	for i in 24: points.append(pos+Vector2(cos(i*TAU/24)*radius.x,sin(i*TAU/24)*radius.y))
	draw_colored_polygon(points,color)

func plant(pos: Vector2, flower: bool=false):
	var p=iso(pos,8)
	box(pos-Vector2(.22,.22),Vector2(.44,.44),13,"c89663","a2754b","78563c")
	pixel(p.x-2,p.y-33,4,25,"5d7d49");pixel(p.x-14,p.y-31,12,7,"8bac5b");pixel(p.x+2,p.y-39,12,8,"719a50")
	pixel(p.x-8,p.y-46,7,13,"a1bd6c");pixel(p.x+2,p.y-53,6,17,"5d8445")
	if flower:pixel(p.x-4,p.y-55,10,7,"e3ae88");pixel(p.x-1,p.y-55,3,4,"f3d78f")

func desk(pos: Vector2):
	for leg in [Vector2(0,0),Vector2(1.5,0),Vector2(0,.8),Vector2(1.5,.8)]:box(pos+leg,Vector2(.15,.15),23,"ad8357","785a3d","624a37")
	box(pos,Vector2(1.7,1),29,"e5be83","b08a55","8f704c")
	box(pos+Vector2(.25,.25),Vector2(.7,.5),31,"fff2cc","d7c59b","c5b895")
	var p=iso(pos+Vector2(.65,.27),32)
	pixel(p.x-8,p.y-1,16,2,"9baf91");pixel(p.x-6,p.y+4,12,1,"afba98")
	var cup=iso(pos+Vector2(1.2,.3),32);pixel(cup.x-4,cup.y-12,8,11,"729282");pixel(cup.x-2,cup.y-13,5,3,"e1d9af")
	pixel(cup.x+4,cup.y-9,3,6,"729282")

func shelf(pos: Vector2):
	box(pos,Vector2(.55,2.2),83,"b99a66","9b7d56","756142")
	for tier in 3:
		for book in 6:
			box(pos+Vector2(.4,.12+book*.32),Vector2(.19,.23),22+tier*23,["83a091","c2926a","d5bf82","6d8689","a78075","779663"][book],"8b7151","74907b")
		box(pos,Vector2(.6,2.2),6+tier*23,"d1b183","b6966a","907751")

func bed(pos: Vector2):
	box(pos,Vector2(1.3,2),14,"aa855e","795d45","76583e")
	box(pos+Vector2(.08,.08),Vector2(1.14,1.84),21,"d6d9b7","afbda1","91a48e")
	box(pos+Vector2(.08,.08),Vector2(1.14,.45),25,"f0e5c4","d4c5a2","b3ae91")
	box(pos+Vector2(.08,.65),Vector2(1.14,1.18),25,"729482","537968","496e60")
	for i in 4:box(pos+Vector2(.08,.73+i*.22),Vector2(1.14,.05),26,"a0b19a","749986","5d8274")

func lamp(pos: Vector2):
	var p=iso(pos);oval(p,Vector2(12,5),Color("6e6a4a"));pixel(p.x-2,p.y-63,4,63,"736b49")
	poly([p+Vector2(-18,-60),p+Vector2(18,-60),p+Vector2(10,-81),p+Vector2(-10,-81)],"edd096")
	pixel(p.x-10,p.y-82,20,3,"f5e1ac");pixel(p.x-4,p.y-60,8,4,"e7b967")

func companion(pos: Vector2, index: int, selected: bool, walking: bool, action: String):
	var p=iso(pos,8); var step=roundf(sin(art_time*14)*2) if walking else 0.0
	var bob=absf(step) if walking else roundf(sin(art_time*2+index)*.5)
	if selected:
		oval(p+Vector2(0,5),Vector2(21,8),Color("e8d99b"));oval(p+Vector2(0,5),Vector2(16,5),Color("658c701c"))
	else:oval(p+Vector2(0,6),Vector2(18,6),Color("213d332b"))
	p.y-=bob
	var coat="81b298" if index==0 else "c98e77"; var dark="355549" if index==0 else "754d45"; var light="b9cba0" if index==0 else "e4bc96"
	pixel(p.x-11,p.y-15,8,18,dark);pixel(p.x+3,p.y-15,8,18,dark)
	pixel(p.x-13,p.y+1+step,11,6,"384b3f");pixel(p.x+2,p.y+1-step,11,6,"384b3f")
	pixel(p.x-15,p.y-37,30,24,coat);pixel(p.x-19,p.y-32+step,6,17,coat);pixel(p.x+13,p.y-32-step,6,17,coat)
	pixel(p.x-19,p.y-17+step,6,6,"e3c59e");pixel(p.x+13,p.y-17-step,6,6,"e3c59e")
	pixel(p.x-11,p.y-34,22,6,light);pixel(p.x-4,p.y-28,8,14,dark);pixel(p.x-2,p.y-26,4,4,"cfbb86")
	pixel(p.x-14,p.y-63,28,26,dark);pixel(p.x-13,p.y-57,26,20,"efdab5");pixel(p.x-16,p.y-60,6,13,dark)
	pixel(p.x-12,p.y-66,24,11,dark);pixel(p.x-7,p.y-70,14,8,dark)
	var blink=fmod(art_time+index,6.0)<.12
	pixel(p.x-8,p.y-50,4,1 if blink else 4,"33473b");pixel(p.x+4,p.y-50,4,1 if blink else 4,"33473b")
	pixel(p.x-10,p.y-44,4,3,"d6a58d");pixel(p.x+7,p.y-44,4,3,"d6a58d");pixel(p.x-2,p.y-41,5,2,"af806a")
	if index==1:
		pixel(p.x-16,p.y-66,32,8,coat);pixel(p.x-21,p.y-61,42,4,coat);pixel(p.x-8,p.y-70,16,5,light)
	if action=="Working":
		pixel(p.x+12,p.y-39,17,14,"eee0ad");pixel(p.x+17,p.y-35,8,2,"8ba17f")
	if action=="Resting":
		draw_string(ThemeDB.fallback_font,p+Vector2(16,-60),"z",HORIZONTAL_ALIGNMENT_LEFT,-1,16,Color("d7dec6"))
	if selected:
		var float_y=sin(art_time*3)*3
		poly([p+Vector2(-5,-86+float_y),p+Vector2(5,-86+float_y),p+Vector2(0,-79+float_y)],"e6ce89")
