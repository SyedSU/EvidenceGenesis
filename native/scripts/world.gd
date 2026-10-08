class_name GenesisWorld
extends GenesisArt

signal interact(kind: String)
signal selected(index: int)
var state: GenesisState
var positions=[Vector2(5.5,8.2),Vector2(8.2,6.8)]
var paths=[[],[]]
var actions=["Idle","Idle"]
var paused=false
var grid=AStarGrid2D.new()
var idle_clock=0.0
var ambient_clock=0.0
var props=[
	{"kind":"shelf","pos":Vector2(3.4,4.1),"size":Vector2(.7,2.3)},
	{"kind":"desk","pos":Vector2(6.8,4.3),"size":Vector2(1.8,1.1)},
	{"kind":"bed","pos":Vector2(8.6,7),"size":Vector2(1.3,2)},
	{"kind":"lamp","pos":Vector2(4.1,7.5),"size":Vector2(.4,.4)},
	{"kind":"plant","pos":Vector2(9.4,3.6),"size":Vector2(.6,.6)},
	{"kind":"bush","pos":Vector2(2.4,10.5),"size":Vector2(.8,.8)}]

func setup(value: GenesisState):
	state=value
	paths=[[],[]];actions=["Idle","Idle"]
	for i in 2:positions[i]=Vector2(float(state.data.crew[i].x),float(state.data.crew[i].y))
	grid.region=Rect2i(1,1,14,14);grid.cell_size=Vector2.ONE
	grid.diagonal_mode=AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	grid.update()
	for x in range(1,15):
		for y in range(1,15):
			grid.set_point_solid(Vector2i(x,y),blocked(Vector2(x+.5,y+.5)))
	for i in 2:
		if blocked(positions[i]):positions[i]=Vector2(5.5+i,8.2)

func blocked(v: Vector2) -> bool:
	if v.x<1.1 or v.y<1.1 or v.x>14.2 or v.y>14.2:return true
	if v.x>=11 and v.y>=3 and v.y<=7.8:return true
	# Two back walls; the front of the cutaway remains open.
	if (v.x>=3 and v.x<=3.3 and v.y>=3 and v.y<=9) or (v.y>=3 and v.y<=3.3 and v.x>=3 and v.x<=10):return true
	for prop in props:
		if Rect2(prop.pos-Vector2(.12,.12),prop.size+Vector2(.24,.24)).has_point(v):return true
	return false

func go(index: int, destination: Vector2):
	var start=Vector2i(positions[index].floor());var finish=Vector2i(destination.floor())
	if not grid.is_in_boundsv(finish) or grid.is_point_solid(finish):return
	var path=grid.get_id_path(start,finish)
	paths[index]=[]
	for cell in path:paths[index].append(Vector2(cell)+Vector2(.5,.5))
	if paths[index].size()>0:paths[index].pop_front()

func _process(delta):
	if state==null:return
	art_time+=delta;ambient_clock+=delta
	if not paused:
		var index=int(state.data.selected)
		if actions[index] not in ["Working","Resting"]:
			var movement=Vector2(float(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT))-float(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT)),float(Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN))-float(Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP)))
			if movement.length()>0:
				paths[index]=[]
				var step=Vector2(movement.x+movement.y,movement.y-movement.x).normalized()*delta*2.6
				var next=positions[index]+step
				if not blocked(Vector2(next.x,positions[index].y)):positions[index].x=next.x
				if not blocked(Vector2(positions[index].x,next.y)):positions[index].y=next.y
				actions[index]="Walking"
			elif paths[index].is_empty():actions[index]="Idle"
		for i in 2:
			if paths[i].size()>0:
				var target: Vector2=paths[i][0]
				positions[i]=positions[i].move_toward(target,delta*2.2)
				if positions[i].distance_to(target)<.03:paths[i].pop_front()
				if actions[i] not in ["Working","Resting"]:actions[i]="Walking"
			elif actions[i]=="Walking":actions[i]="Idle"
		idle_clock+=delta
		if idle_clock>9:
			idle_clock=0
			var other=1-index
			if actions[other]=="Idle":go(other,Vector2(randf_range(4.2,8.8),randf_range(6,10)))
	for i in 2:state.data.crew[i].x=positions[i].x;state.data.crew[i].y=positions[i].y
	if ambient_clock>.033:ambient_clock=0;queue_redraw()

func _unhandled_input(event):
	if state==null or paused:return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode==KEY_TAB:
			selected.emit(1-int(state.data.selected));get_viewport().set_input_as_handled()
		if event.keycode==KEY_E:interact.emit(nearest())
	if event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT:
		var at=get_local_mouse_position()
		for i in 2:
			if at.distance_to(iso(positions[i],35))<30:
				selected.emit(i);return
		if actions[int(state.data.selected)] not in ["Working","Resting"]:go(int(state.data.selected),inverse(at))

func nearest() -> String:
	var here: Vector2=positions[int(state.data.selected)];var distance=2.5;var kind="notebook"
	for prop in props:
		var d=here.distance_to(prop.pos+prop.size/2)
		if d<distance:distance=d;kind=prop.kind
	return kind

func _draw():
	if state==null:return
	draw_rect(Rect2(0,0,1280,720),Color("203b37"))
	poly([Vector2(90,338),Vector2(640,57),Vector2(1190,338),Vector2(640,626)],"19342f")
	box(Vector2(1,1),Vector2(14,14),12,"6b8b61","466445","395a42")
	for x in range(1,15):
		for y in range(1,15):
			var v=Vector2(x,y);var wood=x>=3 and x<10 and y>=3 and y<9
			var colors=["9caf76","95a772"] if not wood else ["d3b985","ddc594"]
			poly([iso(v,12),iso(v+Vector2(1,0),12),iso(v+Vector2.ONE,12),iso(v+Vector2(0,1),12)],colors[(x+y)%2])
			if not wood and (x*13+y*7)%5==0:
				var p=iso(v+Vector2(.4,.6),13);pixel(p.x,p.y-4,2,5,"6b915e");pixel(p.x+3,p.y-2,2,3,"b9c48a")
			if wood:draw_line(iso(v,12),iso(v+Vector2(1,0),12),Color("bba370"),1)
	# Garden path, rippling pond, stepping stones.
	for y in range(9,14):box(Vector2(6,y),Vector2(1.6,1),13,"cabb8d","a59770","a59770")
	for x in range(11,15):
		for y in range(3,8):
			var v=Vector2(x,y);poly([iso(v,14),iso(v+Vector2(1,0),14),iso(v+Vector2.ONE,14),iso(v+Vector2(0,1),14)],"5f8f8e" if (x+y)%2 else "699b99")
			var p=iso(v+Vector2(.5,.5),15)
			pixel(p.x+sin(art_time+x)*3,p.y,14,2,"a2c4af")
	for v in [Vector2(10.7,3),Vector2(10.8,5.7),Vector2(12.2,7.8)]:box(v,Vector2(.55,.4),19,"a3ad92","7d8d78","6e8171")
	# Back walls and window.
	poly([iso(Vector2(3,3),100),iso(Vector2(3,9),100),iso(Vector2(3,9),12),iso(Vector2(3,3),12)],"aab995")
	poly([iso(Vector2(3,3),100),iso(Vector2(10,3),100),iso(Vector2(10,3),12),iso(Vector2(3,3),12)],"d8d9b2")
	draw_line(iso(Vector2(3,9),101),iso(Vector2(3,3),101),Color("78956e"),5)
	draw_line(iso(Vector2(3,3),101),iso(Vector2(10,3),101),Color("aebc8f"),5)
	var win=iso(Vector2(7.3,3),92)
	poly([win,win+Vector2(66,33),win+Vector2(66,79),win+Vector2(0,46)],"688578")
	poly([win+Vector2(4,8),win+Vector2(62,37),win+Vector2(62,70),win+Vector2(4,41)],"b5d0b5")
	poly([win+Vector2(4,33),win+Vector2(18,24),win+Vector2(33,48),win+Vector2(46,44),win+Vector2(62,60),win+Vector2(62,70),win+Vector2(4,41)],"85a785")
	draw_line(win+Vector2(32,22),win+Vector2(32,55),Color("e9dfb5"),4)
	# Rug and objects, sorted with characters by ground depth.
	poly([iso(Vector2(4.4,5.8),13),iso(Vector2(8.3,5.8),13),iso(Vector2(8.3,8.8),13),iso(Vector2(4.4,8.8),13)],"789a83")
	poly([iso(Vector2(4.6,6),14),iso(Vector2(8.1,6),14),iso(Vector2(8.1,8.6),14),iso(Vector2(4.6,8.6),14)],"93af91")
	var entities=props.duplicate()
	for i in 2:entities.append({"kind":"actor","pos":positions[i],"index":i})
	for p in [Vector2(1.5,2.4),Vector2(2.1,12.4),Vector2(12.6,11.5),Vector2(13.4,1.8)]:entities.append({"kind":"tree","pos":p})
	entities.sort_custom(func(a,b):return a.pos.x+a.pos.y<b.pos.x+b.pos.y)
	for entity in entities:
		match entity.kind:
			"tree":tree(entity.pos)
			"shelf":shelf(entity.pos)
			"desk":desk(entity.pos)
			"bed":bed(entity.pos)
			"lamp":lamp(entity.pos)
			"plant":plant(entity.pos,true)
			"bush":tree(entity.pos,1)
			"actor":companion(entity.pos,int(entity.index),int(state.data.selected)==int(entity.index),actions[int(entity.index)]=="Walking",actions[int(entity.index)])
	if state.data.garden:plant(Vector2(8.6,11),true);plant(Vector2(9.4,11.6),true)
	# Floating fireflies: decorative only.
	for i in 8:
		var p=Vector2(320+i*90,240+sin(art_time*.7+i)*70+i*19)
		pixel(p.x,p.y,3,3,"d7d5a0")
	if state.data.night:draw_rect(Rect2(0,0,1280,720),Color("142c4b55"))
