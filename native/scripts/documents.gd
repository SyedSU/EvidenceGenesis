class_name GenesisDocuments
extends RefCounted

static func escape(text: String) -> String:
	return text.replace("&","&amp;").replace("<","&lt;").replace(">","&gt;").replace('"',"&quot;").replace("'","&#39;")

static func html(doc: Dictionary) -> String:
	var blocks="";var list=""
	var ordered=RegEx.new();ordered.compile("^[0-9]+[.)] +")
	for line in String(doc.content).split("\n"):
		if line.begins_with("# ") or line.begins_with("## "):
			if not list.is_empty():blocks+="</"+list+">";list=""
			var level=2 if line.begins_with("## ") else 1
			blocks+="<h"+str(level)+">"+escape(line.substr(level+1))+"</h"+str(level)+">"
		elif line.begins_with("- ") or ordered.search(line)!=null:
			var kind="ul" if line.begins_with("- ") else "ol"
			if list!=kind:
				if not list.is_empty():blocks+="</"+list+">"
				list=kind;blocks+="<"+kind+">"
			blocks+="<li>"+escape(line.substr(2) if kind=="ul" else line.substr(ordered.search(line).get_end()))+"</li>"
		else:
			if not list.is_empty():blocks+="</"+list+">";list=""
			if not line.strip_edges().is_empty():blocks+="<p>"+escape(line)+"</p>"
	if not list.is_empty():blocks+="</"+list+">"
	return '<!doctype html><html lang="en"><meta charset="utf-8"><title>'+escape(doc.title)+'</title><style>body{font:18px/1.6 system-ui;max-width:760px;margin:40px auto;padding:24px;color:#233e36;overflow-wrap:anywhere}small{color:#657568}@media print{body{margin:0}}</style><small>Evidence Genesis · '+escape(doc.mode)+'</small><article dir="auto">'+blocks+'</article></html>'
