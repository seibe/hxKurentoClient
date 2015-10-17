package express;

import haxe.Constraints.Function;
import haxe.extern.Rest;
import haxe.extern.EitherType;
import js.Error;
import js.node.http.Server;

extern class Application
{
	// Public properties
	var locals:Dynamic;
	var mountpath:String;
	
	// Public methods
	function all(path:String, callback:Rest<Function>):Application;
	function delete(path:String, callback:Rest<Function>):Application;
	function disable(name:String):Application;
	function disabled(name:String):Bool;
	function enable(name:String):Application;
	function enabled(name:String):Bool;
	function engine(ext:String, callback:Function):Application;
	
	@:overload(function(path:String, callback:Rest<Function>):Application {})
	function get(name:String):Dynamic;
	
	@:overload(function(path:String, ?callback:Void->Void):Application {})
	@:overload(function(port:Int, ?callback:Void->Void):Application {})
	@:overload(function(port:Int, backlog:Int, ?callback:Void->Void):Application {})
	@:overload(function(port:Int, hostname:String, ?callback:Void->Void):Application {})
	function listen(port:EitherType<Int, String>, hostname:String, backlog:Int, ?callback:Function):Application;
	
	function param(param:String, callback:Function):Application;
	function path():String;
	function post(path:String, callback:Rest<Function>):Application;
	function put(path:String, callback:Rest<Function>):Application;
	
	@:overload(function(view:String, callback:Error->Dynamic->Void):Application {})
	function render(view:String, locals:Dynamic, callback:Error->Dynamic->Void):Application;
	
	function route(path:String):Application;
	function set(name:String, value:Dynamic):Application;
	
	@:overload(function(callback:Rest<Function>):Application {})
	function use(path:String, callback:Rest<Function>):Application;
}
