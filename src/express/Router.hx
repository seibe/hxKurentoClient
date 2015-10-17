package express;

import haxe.extern.Rest;
import haxe.Constraints.Function;

extern class Router
{
	function all(path:String, callback:Rest<Function>):Router;
	function param(param:String, callback:Function):Router;
	function route(path:String):Router;
	
	@:overload(function(callback:Rest<Function>):Router {})
	function use(path:String, callback:Rest<Function>):Router;
}
