import Sys.*;
import sys.io.File;
import sys.FileSystem;

typedef LinkNo = String;  // no need to convert to and from Int
typedef AnchorNo = String;  // no need to convert to and from Int
typedef ProjectNo = String;  // no need to convert to and from Int

typedef ListElem = {
	no : LinkNo,
	anchor : AnchorNo,
	projs : Array<ProjectNo>
}

class D14j {
	static function error(msg:String)
	{
		println('ERROR: $msg');
		exit(1);
	}

	static function usageError(msg:String)
	{
		error('$msg\n\nUsage:\n  d14j <list> (<kml> ...)');
	}

	static function assertFile(path:String)
	{
		if (!FileSystem.exists(path) || FileSystem.isDirectory(path))
			error('$path doesn not exist or is not a file');
	}

	static function readList(path:String)
	{
		assertFile(path);
		var f = File.read(path);
		var csv = new format.csv.Reader("\t");
		csv.open(null, f);
		if (csv.hasNext()) csv.next();  // discard the table header
		var list = new Map<LinkNo,ListElem>();  // store the list in a unondered map (a hash table) for fast O(1) access
		for (rec in csv) {
			var data = { no:rec[0], proj:rec[1], anchor:rec[2] };
			if (!list.exists(data.no)) {
				list[data.no] = { no:data.no, anchor:data.anchor, projs:[data.proj] };
			} else {
				if (list[data.no].anchor != data.anchor)
					error('Anchor mismatch for link ${data.no}');
				list[data.no].projs.push(data.proj);
			}
		}
		f.close();
		return list;
	}

	static function readKml(path:String)
	{
		assertFile(path);
		var kml = Xml.parse(File.getContent(path));
		return kml;
	}

	static function getElem(xml:Xml, name:String)
	{
		var f = xml.elementsNamed(name);
		if (!f.hasNext()) error('Missing element $name');
		return f.next();
	}

	static function getElemName(xml:Xml)
	{
		return StringTools.trim(getElem(xml, "name").firstChild().nodeValue);
	}

	static function getLinkNo(link:Xml)
	{
		var _desc = getElem(link, "description").firstChild().nodeValue;  // escapaed
		var desc = StringTools.htmlUnescape(_desc);

		// get the link no using a regex hack
		var tpat = ~/^<table><tr><td>NO<\/td><td>(\d+)<\/td>/;
		if (!tpat.match(desc)) error('Link ${getElemName(link)}: cannot get NO from description');
		return tpat.matched(1);
	}

	static function parseXmlExcerpt(s:String)
	{
		return Xml.parse(s).firstChild();
	}

	static function makeFolder(dest:Xml, index:Map<String,Xml>, name:String)
	{
		if (index.exists(name)) return index[name];
		var folder = parseXmlExcerpt('<Folder><name>$name</name></Folder>');
		dest.addChild(folder);
		index[name] = folder;
		return folder;
	}

	static function sortEntries(kml:Xml, list:Map<LinkNo,ListElem>)
	{
		kml = Xml.parse(kml.toString());  // clone the entire kml

		var self = getElem(kml, "kml");
		var doc = getElem(self, "Document");
		var base = getElem(doc, "Folder");  // just skip over it

		var rem = [];  // links to remove from base (that have been copied elsewhere)
		var folderIndex = new Map();  // for folders created here

		for (link in base.elementsNamed("Placemark")) {
			var no = getLinkNo(link);
			if (!list.exists(no)) continue;

			var spec = list[no];
			var anchor = makeFolder(doc, folderIndex, 'Anchor ${spec.anchor}');
			for (p in list[no].projs) {
				var proj = makeFolder(anchor, folderIndex, 'Project $p');
				var copy = parseXmlExcerpt(link.toString());
				proj.addChild(copy);
			}
			rem.push(link);  // assuming list[no].projs.length > 0
		}

		for (link in rem) {
			base.removeChild(link);
		}
		return kml;
	}

	static function deriveName(path:String, suffix:String)
	{
		var epat = ~/\.[^.\/\\]+$/;
		if (!epat.match(path))  // no extension
			return path + suffix;
		return '${epat.matchedLeft()}$suffix${epat.matched(0)}';
	}

	static function writeKml(kml, path)
	{
		File.saveContent(path, haxe.xml.Printer.print(kml, true));
	}

	static function main()
	{
		var args = Sys.args();

		if (args.length < 1) usageError("Missing path to list");
		println('Reading (list) ${args[0]}');
		var list = readList(args[0]);

		if (args.length < 2) usageError("Missing a least one input kml");
		for (p in args.slice(1)) {
			println('Reading (kml) $p');
			var kml = readKml(p);
			println("  sorting entries");
			var sorted = sortEntries(kml, list);
			var op = deriveName(p, "-sorted");
			println('  writing the output in $op');
			writeKml(sorted, op);
		}
	}
}
