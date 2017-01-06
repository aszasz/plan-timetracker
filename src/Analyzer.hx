import sys.FileSystem;

import Assertion.*;
import Std.parseInt;
using Literals;
using StringTools;

class Analyzer {
	public static var dump:haxe.io.Output;

	static function info(msg)
		Sys.stderr().writeString('$msg\n');

	static function warn(msg)
		info('WARN: $msg');

	static function error(msg)
	{
		info('ERROR: $msg\n\n');
		throw "Aborted";
	}

	@:allow(Test)
	static function getEntries(content)
	{
		var rough = ~/l(og|go)[ ]+[^`\n]+[ ]+#[a-zA-Z0-9-]+/g;  // pattern used to warn about things that _might_ be malformed log annotations
		var pat = ~/`[\/\\]log[ ]+((from[ ]+(\d+)[h:](\d+)[ ]*'?[ ]+to[ ]+(\d+)[h:](\d+)[ ]*'?)|(((\d+)[h:])?(\d+)[ ]*'?)|((\d+)[ ]*('|[ ]*min)))[ ]+(on|to)[ ]+(#[a-zA-Z0-9_-]+)[^`]*`/g;
		var pos = 0, entries = [];
		while (rough.matchSub(content, pos)) {
			var mpos = rough.matchedPos();
			pos = mpos.pos + mpos.len;

			if (!pat.matchSub(content, mpos.pos - 2) || pat.matchedPos().pos != mpos.pos - 2) {
				// show(pat.matchedPos(), mpos, pos);
				warn('Possibly malformed annotation ignored: ${rough.matched(0)}');
				continue;
			}

			// show([for (i in 0...15) pat.matched(i+1)]);
			var entry:Entry = {
				channel : pat.matched(15),
				duration : 0
			}
			var precise = pat.matched(2) != null;
			if (precise) {
				entry.start = 60.*parseInt(pat.matched(4)) + 3600.*parseInt(pat.matched(3));
				entry.finish = 60.*parseInt(pat.matched(6)) + 3600.*parseInt(pat.matched(5));
				assert(entry.start <= entry.finish, pat.matched(0));
				entry.duration = entry.finish - entry.start;
			} else if (pat.matched(7) != null) {
				entry.duration = 60.*parseInt(pat.matched(10)) + (pat.matched(8) != null ? 3600.*parseInt(pat.matched(9)) : 0);
			} else {
				entry.duration = 60.*parseInt(pat.matched(12));
			}
			// show(pat.matched(0), entry);
			entries.push(entry);
			if (dump != null) {
				dump.writeString(pat.matched(0));
				dump.writeString("\n---\n");
				dump.writeString(haxe.Json.stringify(entry));
				dump.writeString("\n===\n");
			}
		}
		return entries;
	}

	static function prettyDuration(dur:Duration)
	{
		var hours = Math.floor(dur/3600);
		var minutes = StringTools.lpad(Std.string((dur - hours*3600)/60), "0", 2);
		return '${hours}h${minutes}\'';
	}

	static function printSummary(summary:Map<String,Duration>, println)
	{
		var channels = [for (k in summary.keys()) k];
		channels.sort(Reflect.compare);
		var acc = 0.;
		for (c in channels) {
			var dur = summary[c];
			acc += dur;
			println('  $c: ${prettyDuration(dur)}');
		}
		println(' -> total: ${prettyDuration(acc)}');
	}

	static function absorbSummary(summary:Map<String,Duration>, by:Map<String,Duration>)
	{
		for (k in summary.keys())
			if (by.exists(k))
				by[k] += summary[k];
			else
				by[k] = summary[k];
	}

	public static function run(files:Array<String>)
	{
		files = files.copy();
		files.sort(Reflect.compare);

		var total = new Map();
		while (files.length > 0) {
			var file = files.shift();
			switch [FileSystem.exists(file), FileSystem.isDirectory(file)] {
			case [false, _]:
				warn('File does not exist: $file');
			case [true, true]:
				info('=> Entering directory $file');
				var dir = FileSystem.readDirectory(file).map(function (p) return haxe.io.Path.join([file, p]));
				dir.sort(Reflect.compare);
				files = dir.concat(files);
			case [true, false]:
				info('=> $file');
				var entries = getEntries(sys.io.File.getContent(file));
				var daily = new Map();
				for (e in entries) {
					if (daily.exists(e.channel))
						daily[e.channel] += e.duration;
					else
						daily[e.channel] = e.duration;
				}
				printSummary(daily, info);
				absorbSummary(daily, total);
			}
		}
		Sys.println("=> Summary:");
		printSummary(total, Sys.println);
	}
}

