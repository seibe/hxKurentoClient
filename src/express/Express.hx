package express;

import haxe.Constraints.Function;
import js.Node;

@:native("express")
extern class Express
{
	static inline function app():Application return untyped express();
	
	static inline function cookieParser(?secret:Array<String>, ?options:Dynamic):Function {
		var cookieParser = Node.require("cookie-parser");
		return cookieParser(secret, options);
	}
	static inline function session(?options:Dynamic):Function {
		var session = Node.require("express-session");
		return session(options);
	}
	
	@:native("Router")
	static function router(?options:Dynamic):Router;
	
	@:native("static")
	static function staticFunc(root:String, ?options:Dynamic):Function;
	
	private static function __init__() : Void {
		untyped __js__('var express = {0}', Node.require("express"));
	}
}
