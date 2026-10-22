extends SceneTree

class FailPrimaryOnce extends GenesisSaveFiles:
	var victim=""
	var refused=false
	func replace(source: String, destination: String) -> Error:
		if destination==victim and not refused:refused=true;return FAILED
		return super.replace(source,destination)

func _initialize():
	var path="user://concurrent.json"
	var original=GenesisState.new();original.save_path=path
	assert(original.save())
	var first=GenesisState.new();first.save_path=path;first.load_save()
	var stale=GenesisState.new();stale.save_path=path;stale.load_save()
	assert(first.teach("instruction","newest","Keep the newest lesson"))
	var current=FileAccess.get_file_as_bytes(path)
	var backup=FileAccess.get_file_as_bytes(path+".backup")
	assert(not stale.teach("instruction","stale","Must never replace newer work"))
	assert(stale.last_error.contains("changed"))
	assert(stale.actor().lessons.is_empty())
	assert(FileAccess.get_file_as_bytes(path)==current)
	assert(FileAccess.get_file_as_bytes(path+".backup")==backup)
	stale.load_save()
	assert(stale.teach("instruction","after reload","Keep both lessons"))
	assert(stale.actor().lessons.size()==2)
	# A fresh unsynchronized object must not overwrite an existing workshop.
	var fresh=GenesisState.new();fresh.save_path=path
	assert(not fresh.save())
	# The same guard protects profile indexes, not only workshop saves.
	var index="user://concurrent-index.json"
	var owner=GenesisProfiles.new();owner.index_path=index
	assert(owner.persist())
	var old_index=GenesisProfiles.new();old_index.index_path=index;old_index.load_index()
	owner.entries=[{"id":"1","name":"Newest"}];owner.selected="1"
	assert(owner.persist())
	assert(not old_index.persist())
	assert(JSON.parse_string(FileAccess.get_file_as_string(index)).selected=="1")
	# A verified backup created by our own failed transaction is not a stale writer.
	var retry=GenesisState.new();retry.save_path="user://retry-first-backup.json"
	assert(retry.save())
	var fault=FailPrimaryOnce.new();fault.victim=retry.save_path;retry.storage=fault
	assert(not retry.teach("instruction","retry","Keep this lesson"))
	assert(retry.actor().lessons.is_empty())
	assert(retry.teach("instruction","retry","Keep this lesson"))
	print("GENESIS_SAVE_CONCURRENCY_OK: stale workshops and profile indexes preserve newer generations")
	quit()
