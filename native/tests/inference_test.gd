extends SceneTree
var brain: GenesisBrain
var stage=0
var ticks=0
func _initialize():
    call_deferred("run")
func run():
    brain=GenesisBrain.new();root.add_child(brain)
    if not brain.has_method("cancel"):
        push_error("Transport-independent AI cancellation is missing");quit(1);return
    brain.cancel()
    if not ClassDB.class_exists("GenesisLocalInference"):
        push_error("Inference class missing");quit(1);return
    var result=JSON.parse_string(ClassDB.class_call_static("GenesisLocalInference","request","generate","system","hello","test"))
    if result.state!="error":push_error("Unloaded generation accepted");quit(1);return
    var path=OS.get_environment("GENESIS_AI_MODEL")
    if path.is_empty():
        print("GENESIS_NATIVE_AI_CONTRACT_OK: genuine model test blocked without GENESIS_AI_MODEL")
        quit(0);return
    result=JSON.parse_string(ClassDB.class_call_static("GenesisLocalInference","request","load",path,"",""))
    if result.state!="loading":push_error(str(result));quit(1);return
    stage=1
func _process(_delta)->bool:
    if stage==0:return false
    ticks+=1
    if ticks>60000:push_error("Native AI integration timed out");quit(1);return false
    var result=JSON.parse_string(ClassDB.class_call_static("GenesisLocalInference","request","poll","","",""))
    if result.state=="error":push_error(str(result));quit(1);return false
    if stage==1 and result.state=="ready":
        ClassDB.class_call_static("GenesisLocalInference","request","generate","Reply briefly.","What is two plus two?","godot-proof");stage=2
    elif stage==2 and result.state=="completed":
        if result.content.strip_edges().is_empty():push_error("Empty actual model result");quit(1);return false
        print("GENESIS_NATIVE_AI_GENERATION_OK: "+result.content.left(250))
        ClassDB.class_call_static("GenesisLocalInference","request","shutdown","","","");quit(0)

    return false
