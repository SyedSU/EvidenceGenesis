class_name GenesisBrain
extends Node

signal status_changed(text: String)
signal finished(content: String, error: String)
var available=false
var busy=false
var pid=-1
var port=49162
var key=""
var status="Starting your local AI…"
var model_name="genesis-local"
var check: HTTPRequest
var request: HTTPRequest
var attempts=0
var enabled=true
var needs_runtime=false
var native_transport=false
var native_request_id=0
var native_canceling=false
var native_loading=false
const SUPPORT_URL="https://aka.ms/vc14/vc_redist.x64.exe"

func _ready():
	check=HTTPRequest.new();check.timeout=3;add_child(check)
	request=HTTPRequest.new();request.timeout=180;request.body_size_limit=200000;add_child(request)
	check.request_completed.connect(_health)
	request.request_completed.connect(_completed)

func start():
	if native_loading or available:return
	if "--no-brain" in OS.get_cmdline_user_args():
		status="Template mode · local AI disabled for this test";status_changed.emit(status);return
	if OS.get_name()=="Android":
		native_transport=true
		if not ClassDB.class_exists("GenesisLocalInference"):
			status="Local AI support is missing. Template mode remains available.";status_changed.emit(status);return
		# Android accepts only the separately provisioned app-private model.
		var model=ProjectSettings.globalize_path("user://models/genesis.gguf")
		if not FileAccess.file_exists(model):
			status="Local AI model is missing from private storage. Template mode remains available.";status_changed.emit(status);return
		var response=_native_call("load",model)
		native_loading=response.get("state")=="loading"
		status="Verifying and loading the local AI…" if native_loading else response.get("error","Local AI could not load.")
		status_changed.emit(status);return
	var base=OS.get_executable_path().get_base_dir()
	var executable=base.path_join("brain/llama-server.exe" if OS.get_name()=="Windows" else "brain/llama-server")
	var model=base.path_join("model/genesis.gguf")
	if not OS.get_environment("GENESIS_LLAMA_PATH").is_empty():executable=OS.get_environment("GENESIS_LLAMA_PATH")
	if not OS.get_environment("GENESIS_MODEL_PATH").is_empty():model=OS.get_environment("GENESIS_MODEL_PATH")
	if not FileAccess.file_exists(executable) or not FileAccess.file_exists(model):
		status="AI files missing. Keep the brain and model folders beside the game.";status_changed.emit(status);return
	if OS.get_name()=="Windows":
		var system=OS.get_environment("SystemRoot").replace("\\","/").path_join("System32")
		for dependency in ["vcruntime140.dll","vcruntime140_1.dll","msvcp140.dll"]:
			if not FileAccess.file_exists(system.path_join(dependency)) and not FileAccess.file_exists(executable.get_base_dir().path_join(dependency)):
				needs_runtime=true;status="AI needs Microsoft runtime support. Open Settings to install it, then restart.";status_changed.emit(status);return
	var socket=TCPServer.new()
	for candidate in range(49162,49262):
		if socket.listen(candidate,"127.0.0.1")==OK:port=candidate;socket.stop();break
	key=str(randi())+str(Time.get_ticks_usec())+str(randi())
	pid=OS.create_process(executable,["-m",model,"--host","127.0.0.1","--port",str(port),"--alias",model_name,"--ctx-size","4096","--parallel","1","--threads",str(maxi(1,mini(4,OS.get_processor_count()-1))),"--api-key",key,"--no-webui"],false)
	if pid<=0:status="Local AI could not start. Template mode remains available.";status_changed.emit(status);return
	_poll()

func _poll():
	if not is_inside_tree() or available:return
	attempts+=1
	if attempts>60:
		status="AI startup timed out. Restart the game or use template mode.";status_changed.emit(status);return
	check.request("http://127.0.0.1:"+str(port)+"/health",["Authorization: Bearer "+key])

func _health(result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray):
	if result==HTTPRequest.RESULT_SUCCESS and code==200:
		available=true;status="Local AI ready · Qwen 0.5B · offline";status_changed.emit(status)
	else:
		await get_tree().create_timer(1).timeout
		if is_inside_tree():_poll()

func generate(actor: Dictionary, title: String, notes: String, chat=false):
	if busy:finished.emit("","A task is already running.");return
	if not available:finished.emit("",status);return
	busy=true
	var lessons=[];var remaining=2400
	for i in range(actor.lessons.size()-1,-1,-1):
		var lesson=actor.lessons[i];var length=String(lesson.value).length()+String(lesson.key).length()
		if length>remaining:continue
		remaining-=length;lessons.push_front({"kind":lesson.kind,"key":lesson.key,"value":lesson.value})
	var system="You are a helpful companion in Evidence Genesis. Reply in plain text or Markdown. Never claim actions you did not perform. Use the supplied lessons as user preferences. Do not invent citations, facts or tool results. You have no tools."
	if not chat:system+=" Prepare a document from the source notes. Keep their meaning and follow relevant formatting preferences. If the role is Reviewer, review the notes and identify gaps without inventing missing information."
	var prompt={"name":actor.name,"role":actor.role,"lessons":lessons,"title":title,"source_notes":notes}
	var payload={"model":model_name,"messages":[{"role":"system","content":system},{"role":"user","content":JSON.stringify(prompt)}],"max_tokens":700,"temperature":0.3,"stream":false}
	if native_transport:
		native_request_id+=1
		var response=_native_call("generate",system,JSON.stringify(prompt),str(native_request_id))
		if response.get("state")!="generating":
			busy=false;finished.emit("",response.get("error","Local AI could not start."))
		return
	var err=request.request("http://127.0.0.1:"+str(port)+"/v1/chat/completions",["Content-Type: application/json","Authorization: Bearer "+key],HTTPClient.METHOD_POST,JSON.stringify(payload))
	if err!=OK:busy=false;finished.emit("","Could not contact the local AI. Your notes are preserved.")

func _completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray):
	if not busy:return
	busy=false
	if result!=HTTPRequest.RESULT_SUCCESS or code!=200:
		finished.emit("","The local AI could not finish this task. Keep the notes shorter or try again.");return
	var data=JSON.parse_string(body.get_string_from_utf8())
	if not data is Dictionary or not data.get("choices") is Array or data.choices.is_empty():
		finished.emit("","The local AI returned an invalid response.");return
	var message=data.choices[0].get("message",{})
	var content=message.get("content","")
	if not content is String or content.strip_edges().is_empty() or content.length()>20000:
		finished.emit("","The local AI returned an empty or oversized result.");return
	finished.emit(content.strip_edges(),"")

func _native_call(operation: String, first="", second="", third="") -> Dictionary:
	if not ClassDB.class_exists("GenesisLocalInference"):return {"state":"error","error":"Local AI support missing."}
	var raw=ClassDB.class_call_static("GenesisLocalInference","request",operation,first,second,third)
	var data=JSON.parse_string(raw)
	if not data is Dictionary:return {"state":"error","error":"Invalid native AI response."}
	return data

func _process(_delta):
	if not native_transport or not (native_loading or busy or native_canceling):return
	var response=_native_call("poll")
	var state=response.get("state","")
	if native_canceling:
		if state in ["canceled","ready","idle","error"]:
			native_canceling=false;busy=false
			if native_loading:
				native_loading=false;available=false;status="Local AI loading canceled. Restart the game to retry.";status_changed.emit(status)
		return
	if native_loading:
		if state=="ready":
			native_loading=false;available=true;status="Local AI ready · Qwen 0.5B · offline";status_changed.emit(status)
		elif state in ["error","canceled"]:
			native_loading=false;available=false;status=response.get("error","Local AI could not load.");status_changed.emit(status)
		return
	if state in ["completed","error","canceled"]:
		busy=false
		if response.get("request_id","")!=str(native_request_id):return
		var content=response.get("content","")
		if state!="completed":finished.emit("",response.get("error","Local AI could not finish."));return
		if not content is String or content.strip_edges().is_empty() or content.length()>20000:
			finished.emit("","Local AI returned an empty or oversized result.");return
		if response.get("truncated",false):content+="\n\n[Local AI stopped at its output limit; review before approving.]"
		finished.emit(content.strip_edges(),"")

func cancel():
	if native_transport:
		if busy or native_loading:
			native_request_id+=1;native_canceling=true;_native_call("cancel")
	else:
		if request!=null:request.cancel_request()
		busy=false

func _notification(what):
	if what==NOTIFICATION_APPLICATION_PAUSED:
		var had_task=busy
		cancel()
		if had_task:finished.emit("","Local AI canceled while the app entered the background. Your notes are preserved.")

func _exit_tree():
	if native_transport:_native_call("shutdown")
	if pid>0 and OS.is_process_running(pid):OS.kill(pid)
