package ;

import express.Express;
import haxe.Json;
import js.Error;
import js.Node;
import js.node.Path;
import js.node.Url;
import js.Promise;
import kurento.core.MediaPipeline;
import kurento.elements.complexTypes.IceCandidate;
import kurento.elements.WebRtcEndpoint;
import kurento.kurentoClient.KurentoClient;
import minimist.Minimist;
import ws.WsServer;

typedef SessionData = {
	pipeline:MediaPipeline,
	endpoint:WebRtcEndpoint
};

class Main 
{
	private static inline var AS_URI:String = "http://localhost:8080/";
	private static inline var WS_URI:String = "ws://localhost:8888/kurento";
	
	private var _argv:Dynamic;
	private var _sessions:Map<String, SessionData>;
	private var _candidatesQueue:Map<String, Array<Dynamic> >;
	
	static function main() 
	{
		new Main();
	}
	
	function new():Void
	{
		_argv = Minimist.parse(Node.process.argv.slice(2), {
			"default": {
				as_uri: AS_URI,
				ws_uri: WS_URI
			}
		});
		
		var app = Express.app();
		
		/*
		 * Management of _sessions
		 */
		app.use(Express.cookieParser());
		
		var sessionHandler = Express.session({
			secret: "none",
			rolling: true,
			resave: true,
			saveUninitialized: true
		});
		app.use(sessionHandler);
		
		/*
		 * Definition of global variables.
		 */
		_sessions = new Map<String, SessionData>();
		_candidatesQueue = new Map<String, Array<Dynamic> >();
		
		/*
		 * Server startup
		 */
		var asUrl = Url.parse(_argv.as_uri);
		var port = asUrl.port;
		var server = app.listen(port, function() {
			trace("Kurento Tutorial started");
			trace("Open" + Url.format(asUrl) + " with a WebRTC capable browser");
		});
		var wss = new WsServer({
			server: cast server,
			path: "/helloworld"
		});
		
		/*
		 * Management of WebSocket messages
		 */
		wss.on("connection", function(ws:WsSocket):Void {
			var sessionId:String = null;
			var request = ws.upgradeReq;
			var response = {
				writeHead: {}
			};
			
			sessionHandler(request, response, function(err:Dynamic):Void {
				sessionId = request.session.id;
				trace("Connection received with sessionId " + sessionId);
			});
			
			ws.on("error", function(error:Dynamic):Void {
				trace("Connection " + sessionId + " error");
			});
			
			ws.on("close", function():Void {
				trace("Connection " + sessionId + " closed");
				stop(sessionId);
			});
			
			ws.on("message", function(mes:Dynamic):Void {
				var message = Json.parse(mes);
				trace("Connection " + sessionId + " received message ", message);
				
				switch (message.id) {
					case "start":
						sessionId = request.session.id;
						var promise = start(sessionId, ws, message.sdpOffer);
						promise.then(function(sdpAnswer:String):Void {
							ws.send(Json.stringify({
								id: "startResponse",
								sdpAnswer: sdpAnswer
							}));
						}).catchError(function(error:Error):Void {
							ws.send(Json.stringify({
								id: "error",
								message: error
							}));
						});
						
					case "stop":
						stop(sessionId);
						
					case "onIceCandidate":
						onIceCandidate(sessionId, message.candidate);
						
					default:
						ws.send(Json.stringify({
							id: "error",
							message: "Invalid message " + message
						}));
				}
			});
		});
		
		app.use(untyped __js__("express.static({0})", Path.join(Node.__dirname, "static")));
	}
	
	private function start(sessionId:String, ws:WsSocket, sdpOffer:String):Promise<String>
	{
		return new Promise(function(resolve:String->Void, reject:Error->Void)
		{
			if (sessionId == null) {
				reject(new Error("Cannot use undefined sessionId"));
			}
			
			var pipeline:MediaPipeline = null;
			var endpoint:WebRtcEndpoint = null;
			
			// 1. create client
			KurentoClient.getSingleton(_argv.ws_uri)
				.then(function(client:KurentoClient):Promise<MediaPipeline> {
					// 2. create pipeline
					return client.create("MediaPipeline");
				})
				.catchError(function(error:Error):Promise<MediaPipeline> {
					// failed 1
					reject(error);
					return null;
				})
				.then(function(p:MediaPipeline):Promise<WebRtcEndpoint> {
					pipeline = p;
					// 3. create endpoint
					return pipeline.create("WebRtcEndpoint");
				})
				.catchError(function(error:Error):Promise<WebRtcEndpoint> {
					// failed 3
					reject(error);
					return null;
				})
				.then(function(e:WebRtcEndpoint):Promise<Dynamic> {
					endpoint = e;
					if (_candidatesQueue[sessionId] != null) {
						while (_candidatesQueue[sessionId].length > 0) {
							var candidate = _candidatesQueue[sessionId].shift();
							endpoint.addIceCandidate(candidate);
						}
					}
					// 4. connect endpoint (loopback)
					return endpoint.connect(endpoint);
				})
				.then(function(dummy:Dynamic):Promise<Array<Dynamic> > {
					endpoint.on("OnIceCandidate", function(event:IceCandidate):Void {
						var candidate = untyped kurento.register.complexTypes.IceCandidate(event.candidate);
						ws.send(Json.stringify({
							id: "iceCandidate",
							candidate: candidate
						}));
					});
					// 5. offer
					var p1 = endpoint.processOffer(sdpOffer);
					var p2 = endpoint.gatherCandidates();
					return Promise.all([p1, p2]);
				})
				.then(function(results:Array<Dynamic>):Void {
					var sdpAnswer:String = results[0];
					_sessions[sessionId] = {
						"pipeline": pipeline,
						"endpoint": endpoint
					};
					// finish!
					resolve(sdpAnswer);
				})
				.catchError(function(error:Error):Void {
					// failed 3~5
					pipeline.release();
					reject(error);
				});
		});
	}
	
	private function stop(sessionId:String):Void
	{
		if (_sessions[sessionId] != null) {
			var pipeline = _sessions[sessionId].pipeline;
			trace("Releasing pipeline");
			pipeline.release();
			
			_sessions.remove(sessionId);
			_candidatesQueue.remove(sessionId);
		}
	}
	
	private function onIceCandidate(sessionId:String, ic:IceCandidate):Void
	{
		var candidate = untyped kurento.register.complexTypes.IceCandidate(ic);
		
		if (_sessions[sessionId] != null) {
			trace("Sending candidate");
			var endpoint = _sessions[sessionId].endpoint;
			endpoint.addIceCandidate(candidate);
		} else {
			trace("Queueing candidate");
			if (_candidatesQueue[sessionId] == null) {
				_candidatesQueue[sessionId] = new Array<Dynamic>();
			}
			_candidatesQueue[sessionId].push(candidate);
		}
	}
	
}
