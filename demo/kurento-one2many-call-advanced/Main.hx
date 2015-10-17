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
import kurento.elements.RecorderEndpoint;
import kurento.elements.WebRtcEndpoint;
import kurento.kurentoClient.KurentoClient;
import minimist.Minimist;
import ws.WsServer;

typedef SessionData = {
	id:String,
	?ws:WsSocket,
	?pipeline:MediaPipeline,
	endpoint:WebRtcEndpoint,
	?recorder:RecorderEndpoint
};

class Main 
{
	private static inline var AS_URI:String = "http://localhost:8080/";
	private static inline var WS_URI:String = "ws://localhost:8888/kurento";
	private static inline var MV_DIR:String = "file:///tmp";
	private var NO_PRESENTER_MESSAGE(default, never):String = "No active presenter. Try again later...";
	
	private var _argv:Dynamic;
	private var _idCounter:Int;
	private var _candidatesQueue:Map<String, Array<Dynamic> >;
	private var _presenter:SessionData;
	private var _viewers:Map<String, SessionData>;
	
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
		 * Definition of global variables.
		 */
		_idCounter = 0;
		_candidatesQueue = new Map<String, Array<Dynamic> >();
		_presenter = null;
		_viewers = new Map<String, SessionData>();
		
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
			path: "/one2many-advanced"
		});
		
		/*
		 * Management of WebSocket messages
		 */
		wss.on("connection", function(ws:WsSocket):Void {
			var sessionId = getNextUniqueId();
			trace("Connection received with sessionId " + sessionId);
			
			ws.on("error", function(error:Dynamic):Void {
				trace("Connection " + sessionId + " error");
				stop(sessionId);
			});
			
			ws.on("close", function():Void {
				trace("Connection " + sessionId + " closed");
				stop(sessionId);
			});
			
			ws.on("message", function(mes:Dynamic):Void {
				var message = Json.parse(mes);
				trace("Connection " + sessionId + " received message ", message);
				
				switch (message.id) {
					case "presenter":
						var promise = startPresenter(sessionId, ws, message.sdpOffer);
						promise.then(function(sdpAnswer:String):Void {
							ws.send(Json.stringify({
								id: "presenterResponse",
								response: "accepted",
								sdpAnswer: sdpAnswer
							}));
						}).catchError(function(error:Error):Void {
							ws.send(Json.stringify({
								id: "presenterResponse",
								response: "rejected",
								message: error
							}));
						});
						
					case "viewer":
						var promise = startViewer(sessionId, ws, message.sdpOffer);
						promise.then(function(sdpAnswer:String):Void {
							ws.send(Json.stringify({
								id: "viewerResponse",
								response: "accepted",
								sdpAnswer: sdpAnswer
							}));
						}).catchError(function(error:Error):Void {
							ws.send(Json.stringify({
								id: "viewerResponse",
								response: "rejected",
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
		
		app.use(Express.staticFunc(Path.join(Node.__dirname, "static")));
	}
	
	private function startPresenter(sessionId:String, ws:WsSocket, sdpOffer:String):Promise<String>
	{
		return new Promise(function(resolve:String->Void, reject:Error->Void):Void
		{
			clearCandidatesQueue(sessionId);
			
			if (_presenter != null) {
				stop(sessionId);
				reject(new Error("Another user is currently acting as presenter. Try again later ..."));
			}
			
			_presenter = {
				id: sessionId,
				pipeline: null,
				endpoint: null,
				recorder: null
			};
			
			// 1. create client
			KurentoClient.getSingleton(_argv.ws_uri)
				.then(function(client:KurentoClient):Promise<MediaPipeline> {
					if (_presenter == null) return Promise.reject(new Error(NO_PRESENTER_MESSAGE));
					// 2. create pipeline
					return client.create("MediaPipeline");
				})
				.catchError(function(error:Error):Promise<MediaPipeline> {
					// rejected 1
					reject(error);
					return null;
				})
				.then(function(pipeline:MediaPipeline):Promise<Dynamic> {
					if (_presenter == null) return Promise.reject(new Error(NO_PRESENTER_MESSAGE));
					_presenter.pipeline = pipeline;
					// 3. create endpoints
					var p1 = pipeline.create("WebRtcEndpoint");
					// 4. create recoder
					var filepath = Path.join(MV_DIR, Std.string( Date.now().getTime() ) + ".webm");
					var p2 = pipeline.create("RecorderEndpoint", { uri: filepath });
					return Promise.all([p1, p2]);
				})
				.then(function(endpoints:Array<Dynamic>):Promise<Dynamic> {
					if (_presenter == null) return Promise.reject(new Error(NO_PRESENTER_MESSAGE));
					_presenter.endpoint = endpoints[0];
					_presenter.recorder = endpoints[1];
					// 5. connect recorder
					return _presenter.endpoint.connect(_presenter.recorder);
				})
				.then(function(dummy:Dynamic):Promise<Dynamic> {
					_presenter.recorder.record();
					exchangeCandidates(sessionId, _presenter.endpoint, ws);
					// 6. offer
					var p1 = _presenter.endpoint.processOffer(sdpOffer);
					var p2 = _presenter.endpoint.gatherCandidates();
					return Promise.all([p1, p2]);
				})
				.then(function(results:Array<Dynamic>):Promise<RecorderEndpoint> {
					var sdpAnswer:String = results[0];
					if (_presenter == null) return Promise.reject(new Error(NO_PRESENTER_MESSAGE));
					// finish!
					resolve(sdpAnswer);
					return null;
				})
				.catchError(function(error:Error):Promise<MediaPipeline> {
					// rejected 2~6
					stop(sessionId);
					reject(error);
					return null;
				});
		});
	}
	
	private function startViewer(sessionId:String, ws:WsSocket, sdpOffer:String):Promise<String>
	{
		return new Promise(function(resolve:String->Void, reject:Error->Void):Void
		{
			clearCandidatesQueue(sessionId);
			
			if (_presenter == null) {
				stop(sessionId);
				reject(new Error(NO_PRESENTER_MESSAGE));
			}
			
			var sdpAnswer:String = null;
			
			// 1. create endpoint
			_presenter.pipeline.create("WebRtcEndpoint")
				.then(function(endpoint:WebRtcEndpoint):Promise<String> {
					_viewers[sessionId] = {
						id: sessionId,
						endpoint: endpoint,
						ws: ws
					};
					if (_presenter == null) Promise.reject(new Error(NO_PRESENTER_MESSAGE));
					exchangeCandidates(sessionId, endpoint, ws);
					// 2. offer
					return endpoint.processOffer(sdpOffer);
				})
				.then(function(answer:String):Promise<Dynamic> {
					if (_presenter == null) Promise.reject(new Error(NO_PRESENTER_MESSAGE));
					sdpAnswer = answer;
					// 3. connect endpoint
					return _presenter.endpoint.connect(_viewers[sessionId].endpoint);
				})
				.then(function(dummy:Dynamic):Promise<Dynamic> {
					if (_presenter == null) Promise.reject(new Error(NO_PRESENTER_MESSAGE));
					// 4. and more
					return _viewers[sessionId].endpoint.gatherCandidates();
				})
				.then(function(dummy:Dynamic):Promise<Dynamic> {
					// finish!
					resolve(sdpAnswer);
					return null;
				})
				.catchError(function(error:Error):Void {
					// rejected 2~4
					stop(sessionId);
					reject(error);
				});
		});
	}
	
	private function stop(sessionId:String):Void
	{
		if (_presenter != null && _presenter.id == sessionId) {
			for (viewer in _viewers) {
				if (viewer.ws != null) {
					viewer.ws.send(Json.stringify({
						id: "stopCommunication"
					}));
				}
			}
			if (_presenter.recorder != null) {
				_presenter.recorder.stop();
				trace("stop recording");
			}
			_presenter.pipeline.release();
			_presenter = null;
			_viewers = new Map<String, SessionData>();
		}
		else if (_viewers[sessionId] != null) {
			_viewers[sessionId].endpoint.release();
			_viewers.remove(sessionId);
		}
		
		clearCandidatesQueue(sessionId);
	}
	
	private function getNextUniqueId():String
	{
		_idCounter++;
		return Std.string(_idCounter);
	}
	
	private function exchangeCandidates(sessionId:String, endpoint:WebRtcEndpoint, ws:WsSocket):Void
	{
		if (_candidatesQueue[sessionId] != null) {
			while (_candidatesQueue[sessionId].length > 0) {
				var candidate = _candidatesQueue[sessionId].shift();
				endpoint.addIceCandidate(candidate);
			}
		}
		endpoint.on("OnIceCandidate", function(event:IceCandidate):Void {
			var candidate = untyped kurento.register.complexTypes.IceCandidate(event.candidate);
			ws.send(Json.stringify({
				id: "iceCandidate",
				candidate: candidate
			}));
		});
	}
	
	private function clearCandidatesQueue(sessionId:String):Void
	{
		if (_candidatesQueue[sessionId] != null) {
			_candidatesQueue.remove(sessionId);
		}
	}
	
	private function onIceCandidate(sessionId:String, ic:IceCandidate):Void
	{
		var candidate = untyped kurento.register.complexTypes.IceCandidate(ic);
		
		if (_presenter != null && _presenter.id == sessionId && _presenter.endpoint != null) {
			trace("Sending presenter candidate");
			_presenter.endpoint.addIceCandidate(candidate);
		}
		else if (_viewers[sessionId] != null && _viewers[sessionId].endpoint != null) {
			trace("Sending viewer candidate");
			_viewers[sessionId].endpoint.addIceCandidate(candidate);
		}
		else {
			trace("Queueing candidate");
			if (_candidatesQueue[sessionId] == null) {
				_candidatesQueue[sessionId] = new Array<Dynamic>();
			}
			_candidatesQueue[sessionId].push(candidate);
		}
	}
	
}
