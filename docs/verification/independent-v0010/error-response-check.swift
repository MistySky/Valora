import Foundation
final class StubProtocol: URLProtocol, @unchecked Sendable {
 override class func canInit(with request: URLRequest) -> Bool { true }
 override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
 override func startLoading() {
  let httpFailure = request.url!.absoluteString.contains("http-failure")
  let body = httpFailure ? #"{"retcode":0,"code":0,"lyric":"[00:01.00]fixture"}"# : #"{"retcode":1001,"code":1001,"lyric":"[00:01.00]fixture"}"#
  let response = HTTPURLResponse(url:request.url!,statusCode:httpFailure ? 503:200,httpVersion:nil,headerFields:nil)!
  client?.urlProtocol(self,didReceive:response,cacheStoragePolicy:.notAllowed)
  client?.urlProtocol(self,didLoad:Data(body.utf8))
  client?.urlProtocolDidFinishLoading(self)
 }
 override func stopLoading() {}
}
@main struct Check {
 static func main() async throws {
  let config = URLSessionConfiguration.ephemeral
  config.protocolClasses = [StubProtocol.self]
  let session = URLSession(configuration:config)
  for scenario in ["http-failure","api-failure"] {
   let result = await QQMusicLyricsProbe.fetchLyrics(songmid:scenario,session:session)
   let data = try JSONSerialization.data(withJSONObject:result,options:[.sortedKeys])
   print(scenario + ": " + String(decoding:data,as:UTF8.self))
  }
 }
}
