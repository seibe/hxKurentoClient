package minimist;

import js.Node;

@:native("minimist")
extern class Minimist
{
	static inline function parse(args:Array<String>, ?opts:Dynamic):Dynamic return parseArgs(args, opts);
	static inline function parseArgs(args:Array<String>, ?opts:Dynamic):Dynamic {
		return untyped minimist(args, opts);
	}
	
	private static function __init__() : Void {
		untyped __js__('var minimist = {0}', Node.require("minimist"));
	}
}
