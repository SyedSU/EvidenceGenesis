extends RefCounted
var failed=0
var passed=0

class DeleteThenFail extends GenesisSaveFiles:
	var victim=""
	func replace(source: String, destination: String) -> Error:
		if destination==victim:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(destination))
			return FAILED
		return super.replace(source,destination)

class PartialStage extends GenesisSaveFiles:
	func store_checked(path: String, bytes: PackedByteArray) -> String:
		super.store_checked(path,bytes.slice(0,bytes.size()/2))
		return "Injected partial-stage write failure."

class FailAllMoves extends GenesisSaveFiles:
	func replace(source: String, destination: String) -> Error:
		if FileAccess.file_exists(destination):DirAccess.remove_absolute(ProjectSettings.globalize_path(destination))
		return FAILED

class FailRollback extends GenesisSaveFiles:
	var active=""
	var backup_moves=0
	func replace(source: String, destination: String) -> Error:
		if destination==active or (destination==active+".backup" and backup_moves>0):
			if FileAccess.file_exists(destination):DirAccess.remove_absolute(ProjectSettings.globalize_path(destination))
			return FAILED
		if destination==active+".backup":backup_moves+=1
		return super.replace(source,destination)

class PartialBackupRestore extends FailAllMoves:
	var backup=""
	func store_checked(path: String, bytes: PackedByteArray) -> String:
		if path==backup:
			super.store_checked(path,bytes.slice(0,bytes.size()/2));return "Injected partial backup recovery."
		return super.store_checked(path,bytes)

class UncertainMove extends GenesisSaveFiles:
	var victim=""
	func native_replace(source: String, destination: String) -> int:
		var status=super.native_replace(source,destination)
		return 2 if status==0 and destination==victim else status

class UncertainRollback extends GenesisSaveFiles:
	var active=""
	var moves=0
	func native_replace(source: String, destination: String) -> int:
		if destination==active:return 1
		var status=super.native_replace(source,destination)
		if destination==active+".backup":
			moves+=1
			if status==0 and moves==2:return 2
		return status

class FailSync extends GenesisSaveFiles:
	func sync_file(_path: String) -> Error:return FAILED

class MissingAdapter extends GenesisSaveFiles:
	func native_available() -> bool:return false

func retained_bytes(prefix: String, bytes: String) -> bool:
	for name in DirAccess.get_files_at("user://save-safety"):
		if name.begins_with(prefix) and FileAccess.get_file_as_string("user://save-safety/"+name)==bytes:return true
	return false

func check(condition: bool, label: String):
	if condition:passed+=1;print("SAVE_PASS: "+label)
	else:failed+=1;print("SAVE_FAIL: "+label)

func run() -> bool:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://save-safety"))
	var sync_state=GenesisState.new();sync_state.save_path="user://save-safety/sync-failure.json"
	check(sync_state.save(),"sync baseline")
	var sync_before=FileAccess.get_file_as_string(sync_state.save_path)
	sync_state.storage=FailSync.new();sync_state.data.stars=4
	check(not sync_state.save(),"failed native disk sync rejects save")
	check(FileAccess.get_file_as_string(sync_state.save_path)==sync_before,"failed native sync preserves active bytes")
	check(not FileAccess.file_exists(sync_state.save_path+".backup"),"failed native sync never advances backup")
	var absent=GenesisState.new();absent.save_path="user://save-safety/adapter-missing.json";absent.storage=MissingAdapter.new()
	check(not absent.save(),"missing native adapter refuses buffered fallback")
	check(not FileAccess.file_exists(absent.save_path),"missing adapter creates no active save")
	for boundary in ["primary","backup"]:
		var unknown=GenesisState.new();unknown.save_path="user://save-safety/uncertain-"+boundary+".json"
		check(unknown.save(),"uncertain "+boundary+" baseline")
		unknown.data.stars=1;check(unknown.save(),"uncertain "+boundary+" second generation")
		var old=FileAccess.get_file_as_string(unknown.save_path)
		var older=FileAccess.get_file_as_string(unknown.save_path+".backup")
		var uncertain_adapter=UncertainMove.new();uncertain_adapter.victim=unknown.save_path+(".backup" if boundary=="backup" else "")
		unknown.storage=uncertain_adapter;unknown.data.stars=2
		check(not unknown.save(),"uncertain "+boundary+" sync reports failure")
		check(uncertain_adapter.uncertain,"uncertain "+boundary+" locks further writes")
		check(FileAccess.get_file_as_string(unknown.save_path+".backup")==old,"uncertain "+boundary+" retains previous generation in backup")
		check(retained_bytes("uncertain-"+boundary+".json.backup.tmp-",older),"uncertain "+boundary+" retains older recovery stage")
		var current=FileAccess.get_file_as_string(unknown.save_path)
		check(not unknown.save() and FileAccess.get_file_as_string(unknown.save_path)==current,"uncertain "+boundary+" repeated save cannot advance disk")
		check(unknown.last_error.contains("Reload"),"uncertain "+boundary+" gives reload instruction")
	var rollback_unknown=GenesisState.new();rollback_unknown.save_path="user://save-safety/uncertain-rollback.json"
	check(rollback_unknown.save(),"uncertain rollback baseline")
	var rollback_older=FileAccess.get_file_as_string(rollback_unknown.save_path)
	rollback_unknown.data.stars=1;check(rollback_unknown.save(),"uncertain rollback second generation")
	var rollback_before=FileAccess.get_file_as_string(rollback_unknown.save_path)
	var rollback_adapter=UncertainRollback.new();rollback_adapter.active=rollback_unknown.save_path;rollback_unknown.storage=rollback_adapter;rollback_unknown.data.stars=2
	check(not rollback_unknown.save(),"uncertain rollback reports failure")
	check(rollback_adapter.uncertain,"uncertain rollback locks further writes")
	check(FileAccess.get_file_as_string(rollback_unknown.save_path)==rollback_before and FileAccess.get_file_as_string(rollback_unknown.save_path+".backup")==rollback_older,"uncertain rollback actual generations preserved")
	check(rollback_unknown.last_error.contains("Reload") and rollback_unknown.last_error.contains(rollback_unknown.save_path+".backup"),"uncertain rollback immediately identifies backup and reload")
	check(not rollback_unknown.last_error.contains(".tmp-"),"uncertain rollback never names consumed stage as retained")
	var state=GenesisState.new();state.save_path="user://save-safety/backup-blocked.json"
	check(state.save(),"initial save")
	var original=FileAccess.get_file_as_string(state.save_path)
	DirAccess.make_dir_absolute(ProjectSettings.globalize_path(state.save_path+".backup"))
	state.data.stars=7
	check(not state.save(),"backup directory rejects save")
	check(FileAccess.get_file_as_string(state.save_path)==original,"backup failure preserves active bytes")
	check(not state.last_error.is_empty(),"backup failure reports error")
	var bad=GenesisState.new();bad.save_path="user://save-safety/invalid-candidate.json";check(bad.save(),"candidate baseline")
	var baseline=FileAccess.get_file_as_string(bad.save_path);bad.data.crew[0].energy=-2
	check(not bad.save(),"invalid candidate refuses persistence")
	check(FileAccess.get_file_as_string(bad.save_path)==baseline,"invalid candidate preserves original")
	var care=GenesisState.new();care.save_path="user://save-safety/care-rollback.json";check(care.save(),"care baseline")
	var before=care.data.duplicate(true);care.save_enabled=false
	var message=care.feed();check(care.data==before,"failed feed rolls back berry energy and progress");check(message==care.last_error and not message.is_empty(),"failed feed reports failure")
	message=care.harvest();check(care.data==before,"failed harvest rolls back berries and cooldown");check(message==care.last_error and not message.is_empty(),"failed harvest reports failure")
	check(care.call("rest",0)==false,"failed rest reports false");check(care.data==before,"failed rest rolls back energy and progress")
	var profiles=GenesisProfiles.new();profiles.index_path="user://save-safety/index.json"
	var first=profiles.create("Protected first");check(first!=null,"first profile exists")
	var first_id=profiles.selected;var index_before=FileAccess.get_file_as_string(profiles.index_path)
	DirAccess.make_dir_absolute(ProjectSettings.globalize_path(profiles.index_path+".backup"))
	check(profiles.create("Must not select") == null,"blocked index backup rejects new selection")
	check(profiles.selected==first_id and profiles.entries.size()==1,"failed profile creation preserves previous selection")
	check(FileAccess.get_file_as_string(profiles.index_path)==index_before,"failed profile persistence preserves index")
	var staged=GenesisState.new();staged.save_path="user://save-safety/stage.json";check(staged.save(),"stage baseline")
	var staged_before=FileAccess.get_file_as_string(staged.save_path);staged.storage=PartialStage.new();staged.data.stars=9
	check(not staged.save(),"partial stage rejects save");check(FileAccess.get_file_as_string(staged.save_path)==staged_before,"partial stage preserves active bytes")
	var first_stage=GenesisState.new();first_stage.save_path="user://save-safety/first-stage.json";first_stage.storage=PartialStage.new()
	check(not first_stage.save(),"partial first-save stage rejects persistence")
	check(not FileAccess.file_exists(first_stage.save_path),"partial first-save stage never becomes active")
	var rename=GenesisState.new();rename.save_path="user://save-safety/rename.json";check(rename.save(),"rename baseline")
	rename.data.stars=1;check(rename.save(),"rename second generation")
	var rename_before=FileAccess.get_file_as_string(rename.save_path);var backup_before=FileAccess.get_file_as_string(rename.save_path+".backup")
	var broken=DeleteThenFail.new();broken.victim=rename.save_path;rename.storage=broken;rename.data.stars=8
	check(not rename.save(),"delete-before-failed-move reports failure")
	check(FileAccess.get_file_as_string(rename.save_path)==rename_before,"failed move restores missing active")
	check(FileAccess.get_file_as_string(rename.save_path+".backup")==backup_before,"failed move preserves previous backup")
	var missing=GenesisState.new();missing.save_path="user://save-safety/missing.json";check(missing.save(),"recovery baseline")
	missing.data.stars=2;check(missing.save(),"recovery generation")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(missing.save_path))
	var recovered=GenesisState.new();recovered.save_path=missing.save_path;recovered.load_save()
	check(recovered.save_enabled and recovered.data.stars==0 and recovered.last_error.contains("Recovered"),"missing primary recovers validated backup")
	var corrupt_path="user://save-safety/corrupt.json";var corrupt=FileAccess.open(corrupt_path,FileAccess.WRITE);corrupt.store_string("invalid preserved bytes");corrupt.close()
	var damaged=GenesisState.new();damaged.save_path=corrupt_path;damaged.load_save()
	check(not damaged.save_enabled and not damaged.save(),"corrupt save disables writes")
	check(FileAccess.get_file_as_string(corrupt_path)=="invalid preserved bytes","corrupt original preserved byte for byte")
	var quarantines=DirAccess.get_files_at("user://save-safety");var quarantined=false
	for name in quarantines:
		if name.begins_with("corrupt.json.corrupt-"):quarantined=FileAccess.get_file_as_string("user://save-safety/"+name)=="invalid preserved bytes"
	check(quarantined,"corrupt bytes quarantined without replacing original")
	var bounded=GenesisState.new();bounded.save_path="user://save-safety/bounded.json"
	for i in 60:bounded.data.tasks.append({"id":str(i),"title":"Old","notes":"Notes","actor":0,"mode":"Template","status":"failed","error":"","document":""})
	check(bounded.save(),"bounded task baseline");var tasks_before=bounded.data.duplicate(true);bounded.save_enabled=false
	check(bounded.queue_task("New","Notes",0,"Template").is_empty() and bounded.data==tasks_before,"failed task queue preserves evicted history")
	var sole=GenesisState.new();sole.save_path="user://save-safety/sole.json";check(sole.save(),"sole backup baseline");sole.data.stars=1;check(sole.save(),"sole backup generation")
	var sole_bytes=FileAccess.get_file_as_string(sole.save_path+".backup");DirAccess.remove_absolute(ProjectSettings.globalize_path(sole.save_path))
	sole.storage=FailAllMoves.new();sole.data.stars=2;check(not sole.save(),"missing primary failed replacement rejected")
	check(FileAccess.file_exists(sole.save_path+".backup") and FileAccess.get_file_as_string(sole.save_path+".backup")==sole_bytes,"failed replacement never rewrites sole unchanged backup")
	var rollback=GenesisState.new();rollback.save_path="user://save-safety/rollback-backup.json";check(rollback.save(),"rollback baseline");rollback.data.stars=1;check(rollback.save(),"rollback generation")
	var prior=FileAccess.get_file_as_string(rollback.save_path+".backup");var active_prior=FileAccess.get_file_as_string(rollback.save_path)
	var rollback_fault=FailRollback.new();rollback_fault.active=rollback.save_path;rollback.storage=rollback_fault;rollback.data.stars=2
	check(not rollback.save(),"backup rollback failure rejects transaction")
	check(FileAccess.get_file_as_string(rollback.save_path)==active_prior,"backup rollback failure retains active original")
	check(retained_bytes("rollback-backup.json.backup",prior),"backup rollback failure retains verified previous backup stage")
	check(rollback.last_error.contains("user://"),"backup rollback failure reports recovery file location")
	var restore=GenesisState.new();restore.save_path="user://save-safety/restore-backup.json";check(restore.save(),"backup restore baseline");restore.data.stars=1;check(restore.save(),"backup restore generation")
	var restore_prior=FileAccess.get_file_as_string(restore.save_path+".backup");var restore_fault=PartialBackupRestore.new();restore_fault.backup=restore.save_path+".backup";restore.storage=restore_fault;restore.data.stars=2
	check(not restore.save(),"backup replacement failure rejects transaction")
	check(retained_bytes("restore-backup.json.backup",restore_prior),"failed backup restoration retains verified original backup")
	check(restore.last_error.contains("user://"),"failed backup restoration reports recovery location")
	var backup_fault=GenesisState.new();backup_fault.save_path="user://save-safety/backup-move.json";check(backup_fault.save(),"backup move baseline");backup_fault.data.stars=1;check(backup_fault.save(),"backup move generation")
	var backup_active=FileAccess.get_file_as_string(backup_fault.save_path);var backup_old=FileAccess.get_file_as_string(backup_fault.save_path+".backup")
	var blocked_backup_move=DeleteThenFail.new();blocked_backup_move.victim=backup_fault.save_path+".backup";backup_fault.storage=blocked_backup_move;backup_fault.data.stars=2
	check(not backup_fault.save() and FileAccess.get_file_as_string(backup_fault.save_path)==backup_active,"failed backup move preserves active original")
	check(retained_bytes("backup-move.json.backup",backup_old),"failed backup move retains original backup despite failed recovery")
	var invalid_utf8=JSON.stringify(GenesisState.new().data).to_utf8_buffer()
	var name_offset=invalid_utf8.get_string_from_utf8().find("Milo");invalid_utf8[name_offset]=255
	var encoding_path="user://save-safety/encoding.json";var encoding=FileAccess.open(encoding_path,FileAccess.WRITE);encoding.store_buffer(invalid_utf8);encoding.close()
	var encoding_state=GenesisState.new();encoding_state.save_path=encoding_path;encoding_state.load_save()
	check(not encoding_state.save_enabled,"invalid UTF8 save rejected instead of repairing text")
	check(FileAccess.get_file_as_bytes(encoding_path)==invalid_utf8,"invalid encoding original bytes preserved")
	var unicode_state=GenesisState.new();unicode_state.save_path="user://save-safety/unicode.json";unicode_state.data.crew[0].name="سلام 🎮"
	check(unicode_state.save(),"valid UTF8 save accepted")
	var unicode_reload=GenesisState.new();unicode_reload.save_path=unicode_state.save_path;unicode_reload.load_save()
	check(unicode_reload.data.crew[0].name=="سلام 🎮","valid Unicode memory round trips exactly")
	var encoding_cases=[PackedByteArray([0xc0,0x80]),PackedByteArray([0xe0,0x80,0xa0]),PackedByteArray([0xed,0xa0,0x80]),PackedByteArray([0xf0,0x80,0x80,0x80]),PackedByteArray([0xf4,0x90,0x80,0x80]),PackedByteArray([0xe2,0x82]),PackedByteArray([0xc2,0x41]),PackedByteArray([0xf5,0x80,0x80,0x80])]
	for bytes in encoding_cases:check(not unicode_state.storage.valid_utf8(bytes),"UTF8 rejects overlong surrogate out-of-range truncated or invalid continuation fixture "+str(bytes))
	print("GENESIS_SAVE_SAFETY: "+str(passed)+" passed, "+str(failed)+" failed")
	return failed==0
