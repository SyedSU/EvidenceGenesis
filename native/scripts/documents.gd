class_name GenesisDocuments
extends RefCounted

static func escape(text: String) -> String:
	return text.replace("&","&amp;").replace("<","&lt;").replace(">","&gt;").replace('"',"&quot;").replace("'","&#39;")

static func html(doc: Dictionary) -> String:
	var blocks="";var list=""
	for line in String(doc.content).split("\n"):
		if line.begins_with("# ") or line.begins_with("## "):
			if not list.is_empty():blocks+="</"+list+">";list=""
			var level=2 if line.begins_with("## ") else 1
			blocks+="<h"+str(level)+">"+escape(line.substr(level+1))+"</h"+str(level)+">"
		elif line.begins_with("- "):
			if list!="ul":
				if not list.is_empty():blocks+="</"+list+">"
				list="ul";blocks+="<ul>"
			blocks+="<li>"+escape(line.substr(2))+"</li>"
		else:
			if not list.is_empty():blocks+="</"+list+">";list=""
			if not line.strip_edges().is_empty():blocks+="<p>"+escape(line)+"</p>"
	if not list.is_empty():blocks+="</"+list+">"
	return '<!doctype html><html lang="en"><meta charset="utf-8"><title>'+escape(doc.title)+'</title><style>body{font:18px/1.6 system-ui;max-width:760px;margin:40px auto;padding:24px;color:#233e36;overflow-wrap:anywhere}small{color:#657568}@media print{body{margin:0}}</style><small>Evidence Genesis · '+escape(doc.mode)+'</small><article dir="auto">'+blocks+'</article></html>'
