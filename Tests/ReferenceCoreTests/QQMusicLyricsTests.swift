import XCTest
@testable import ReferenceCore

final class QQMusicLyricsTests: XCTestCase {
    private func candidate(mid: String = "mid-1", title: String = "晴天",
                           artist: String = "周杰伦", album: String = "叶惠美",
                           duration: Double? = 269, id: Int64? = 97773) -> QQMusicCandidate {
        QQMusicCandidate(songmid: mid, songID: id, title: title,
                         artist: artist, album: album, duration: duration)
    }

    func testExactStudioMatchRequiresMetadataAgreement() {
        let request = QQMusicSample(title: "晴天", artist: "周杰伦", album: "叶惠美", duration: 269)
        XCTAssertEqual(QQMusicMatcher.match(request, candidates: [candidate()]), .matched(candidate()))
    }

    func testLiveVersionIsNotChosenForStudioRequest() {
        let request = QQMusicSample(title: "晴天", artist: "周杰伦", album: "叶惠美", duration: 269)
        let live = candidate(title: "晴天 (Live)", album: "演唱会", duration: 249)
        XCTAssertEqual(QQMusicMatcher.match(request, candidates: [live]), .noMatch(.versionMismatch))
    }

    func testExplicitLiveRequestMatchesOnlyLiveVersion() {
        let request = QQMusicSample(title: "晴天 (Live)", artist: "周杰伦",
                                    album: "演唱会", duration: 249)
        let studio = candidate()
        let live = candidate(mid: "live", title: "晴天 (Live)", album: "演唱会", duration: 249)
        XCTAssertEqual(QQMusicMatcher.match(request, candidates: [studio, live]), .matched(live))
    }

    func testAlbumMismatchIsRejected() {
        let request = QQMusicSample(title: "晴天", artist: "周杰伦", album: "叶惠美", duration: 269)
        let other = candidate(album: "精选集")
        XCTAssertEqual(QQMusicMatcher.match(request, candidates: [other]), .noMatch(.albumMismatch))
    }

    func testExactAlbumIsPreferredOverUnknownAlbum() {
        let request = QQMusicSample(title: "晴天", artist: "周杰伦", album: "叶惠美", duration: 269)
        let unknown = candidate(mid: "unknown", album: "", duration: 268)
        let exact = candidate(mid: "exact")
        XCTAssertEqual(QQMusicMatcher.match(request, candidates: [unknown, exact]), .matched(exact))
        XCTAssertEqual(QQMusicMatcher.match(request, candidates: [unknown]), .noMatch(.albumMismatch))
    }

    func testDurationMismatchIsRejected() {
        let request = QQMusicSample(title: "晴天", artist: "周杰伦", album: "叶惠美", duration: 269)
        let short = candidate(duration: 249)
        XCTAssertEqual(QQMusicMatcher.match(request, candidates: [short]), .noMatch(.durationMismatch))
    }

    func testAmbiguousCandidatesAreNotPickedByPosition() {
        let request = QQMusicSample(title: "晴天", artist: "周杰伦", album: "叶惠美", duration: 269)
        let one = candidate(mid: "one")
        let two = candidate(mid: "two")
        XCTAssertEqual(QQMusicMatcher.match(request, candidates: [one, two]), .noMatch(.ambiguous))
    }

    func testIncompleteSoloArtistAcceptsCollaborationButNotMaleVersion() {
        let request = QQMusicSample(title: "知否知否", artist: "胡夏",
                                    album: "知否知否应是绿肥红瘦 电视剧原声带", duration: 276)
        let collaboration = QQMusicCandidate(songmid: "collab", songID: 1,
            title: "知否知否", artist: "胡夏 / 郁可唯",
            album: "知否知否应是绿肥红瘦 电视剧原声带", duration: 276)
        let male = QQMusicCandidate(songmid: "male", songID: 2,
            title: "知否知否 (男声版)", artist: "胡夏",
            album: "知否知否应是绿肥红瘦 电视剧原声带", duration: 276)
        XCTAssertEqual(QQMusicMatcher.match(request, candidates: [male, collaboration]),
                       .matched(collaboration))
        XCTAssertEqual(QQMusicMatcher.match(request, candidates: [male]),
                       .noMatch(.versionMismatch))
    }

    func testMissingRequestedCollaboratorIsStillRejected() {
        let request = QQMusicSample(title: "知否知否", artist: "胡夏 / 郁可唯",
                                    album: "知否知否应是绿肥红瘦 电视剧原声带", duration: 276)
        let partial = QQMusicCandidate(songmid: "partial", title: "知否知否",
            artist: "胡夏", album: "知否知否应是绿肥红瘦 电视剧原声带", duration: 276)
        XCTAssertEqual(QQMusicMatcher.match(request, candidates: [partial]),
                       .noMatch(.artistMismatch))
    }

    func testArtistMismatchAndEmptyCandidates() {
        let request = QQMusicSample(title: "晴天", artist: "周杰伦", album: "叶惠美", duration: 269)
        XCTAssertEqual(QQMusicMatcher.match(request, candidates: [candidate(artist: "其他人")]),
                       .noMatch(.artistMismatch))
        XCTAssertEqual(QQMusicMatcher.match(request, candidates: []), .noMatch(.noCandidates))
    }

    func testRemixAndInstrumentalTagsAreTreatedAsVersions() {
        let request = QQMusicSample(title: "晴天", artist: "周杰伦", album: "叶惠美", duration: 269)
        let remix = candidate(title: "晴天 (Remix)", album: "叶惠美", duration: 269)
        XCTAssertEqual(QQMusicMatcher.match(request, candidates: [remix]), .noMatch(.versionMismatch))
    }

    func testSearchParserAcceptsCurrentShapeAndLegacyJSONP() throws {
        let current = """
        {"code":0,"data":{"song":{"list":[{"mid":"0039MnYb0qxYhV","id":97773,
        "title":"晴天","interval":269,"album":{"name":"叶惠美"},
        "singer":[{"name":"周杰伦"}]}]}}}
        """
        let parsed = try QQMusicSearchParser.parse(Data(current.utf8))
        XCTAssertEqual(parsed, [candidate(mid: "0039MnYb0qxYhV")])

        let wrapped = "MusicJsonCallback(" + current + ")"
        XCTAssertEqual(try QQMusicSearchParser.parse(Data(wrapped.utf8)),
                       [candidate(mid: "0039MnYb0qxYhV")])
    }

    func testSearchParserReportsAPIError() {
        let data = Data(#"{"code":-1,"data":{"song":{"list":[]}}}"#.utf8)
        XCTAssertThrowsError(try QQMusicSearchParser.parse(data)) { error in
            XCTAssertEqual(error as? QQMusicSearchParseError, .apiCode(-1))
        }
    }


    func testLyricHTTPFailureWinsOverParseableBody() {
        let body = Data(#"{"retcode":0,"code":0,"lyric":"[00:01.00]fixture"}"#.utf8)
        XCTAssertEqual(QQMusicLyricEvaluator.evaluate(status: 503, data: body),
                       .failure(.httpStatus(503)))
    }

    func testLyricAPIErrorWinsOverLyricBody() {
        let body = Data(#"{"retcode":1001,"code":1001,"subcode":0,"lyric":"[00:01.00]fixture"}"#.utf8)
        XCTAssertEqual(QQMusicLyricEvaluator.evaluate(status: 200, data: body),
                       .failure(.apiCode(code: 1001, retcode: 1001, subcode: 0)))
    }

    func testLyricMalformedAndNoLyricsAreDistinct() {
        XCTAssertEqual(QQMusicLyricEvaluator.evaluate(status: 200, data: Data("not json".utf8)),
                       .failure(.invalidJSON))
        let noLyrics = Data(#"{"retcode":0,"code":0}"#.utf8)
        XCTAssertEqual(QQMusicLyricEvaluator.evaluate(status: 200, data: noLyrics), .noLyrics)
        let emptyLyrics = Data(#"{"retcode":0,"code":0,"lyric":""}"#.utf8)
        XCTAssertEqual(QQMusicLyricEvaluator.evaluate(status: 200, data: emptyLyrics), .noLyrics)
    }

    func testLyricSuccessfulEvaluationKeepsTimedContent() {
        let body = Data(#"{"retcode":0,"code":0,"lyric":"[00:01.00]fixture"}"#.utf8)
        guard case .timedLRC(let lines, let metadata) = QQMusicLyricEvaluator.evaluate(status: 200, data: body) else {
            return XCTFail("expected timed lyric")
        }
        XCTAssertEqual(lines, [LyricLine(start: 1, text: "fixture")])
        XCTAssertNil(metadata.title)
    }

    func testSearchHTTPAndAPIStatusAreGatedBeforeCandidates() {
        let successBody = Data(#"{"code":0,"data":{"song":{"list":[{"mid":"m","id":1,"title":"晴天","album":{"name":"叶惠美"},"singer":[{"name":"周杰伦"}],"interval":269}]}}}"#.utf8)
        XCTAssertEqual(QQMusicSearchEvaluator.evaluate(status: 503, data: successBody),
                       .failure(.httpStatus(503)))
        XCTAssertEqual(QQMusicSearchEvaluator.evaluate(status: 200, data: successBody),
                       .success([QQMusicCandidate(songmid: "m", songID: 1, title: "晴天",
                                                  artist: "周杰伦", album: "叶惠美", duration: 269)]))
        let apiError = Data(#"{"code":1001,"data":{"song":{"list":[{"mid":"m","title":"晴天"}]}}}"#.utf8)
        XCTAssertEqual(QQMusicSearchEvaluator.evaluate(status: 200, data: apiError),
                       .failure(.apiCode(code: 1001, retcode: nil, subcode: nil)))
        let missingCode = Data(#"{"data":{"song":{"list":[]}}}"#.utf8)
        XCTAssertEqual(QQMusicSearchEvaluator.evaluate(status: 200, data: missingCode),
                       .failure(.missingStructure))
    }

    func testQRCHTTPAndBusinessStatusAreGated() {
        let content = #"<result>0</result><content><![CDATA[0123abcdef]]></content>"#
        XCTAssertEqual(QQMusicQRCEvaluator.evaluate(status: 503, data: Data(content.utf8)),
                       .failure(.httpStatus(503)))
        let noContent = #"<result>-1</result>"#
        XCTAssertEqual(QQMusicQRCEvaluator.evaluate(status: 200, data: Data(noContent.utf8)),
                       .noContent(result: "-1"))
        let businessError = #"<result>5</result>"#
        XCTAssertEqual(QQMusicQRCEvaluator.evaluate(status: 200, data: Data(businessError.utf8)),
                       .failure(.businessCode("5")))
        let missingResult = #"<content><![CDATA[abc]]></content>"#
        XCTAssertEqual(QQMusicQRCEvaluator.evaluate(status: 200, data: Data(missingResult.utf8)),
                       .failure(.missingStructure))
        let success = #"<result>0</result><content type="file"><![CDATA[0123abcdef]]></content>"#
        XCTAssertEqual(QQMusicQRCEvaluator.evaluate(status: 200, data: Data(success.utf8)),
                       .content(characterCount: 10, looksLikeHex: true))
    }

    func testLyricResponseSupportsPlainAndBase64Payloads() throws {
        let lrc = "[ti:晴天]\n[00:00.00]晴天\n[00:02.25]词：周杰伦"
        let plain = try XCTUnwrap(QQMusicLyricResponse(data: Data(#"{"retcode":0,"code":0,"lyric":"\#(lrc.replacingOccurrences(of: "\n", with: "\\n"))"}"#.utf8)))
        XCTAssertEqual(plain.lyric, lrc)
        let encoded = Data(lrc.utf8).base64EncodedString()
        let base64 = try XCTUnwrap(QQMusicLyricResponse(data: Data(#"{"retcode":0,"code":0,"lyric":"\#(encoded)"}"#.utf8)))
        XCTAssertEqual(base64.lyric, lrc)
    }

    func testLRCTimedLinesMetadataMultipleTimestampsAndOffset() {
        let raw = """
        [ti:晴天]
        [ar:周杰伦]
        [offset:-500]
        [00:02.25][00:12.25]第一句
        [00:04.50]第二句
        [bad]不是时间戳
        """
        guard case .timed(let lines, let metadata) = LRCParser.parse(raw) else {
            return XCTFail("expected timed lyrics")
        }
        XCTAssertEqual(metadata.title, "晴天")
        XCTAssertEqual(metadata.artist, "周杰伦")
        XCTAssertEqual(metadata.offsetMilliseconds, -500)
        XCTAssertEqual(lines.map(\.start), [1.75, 11.75, 4.0])
        XCTAssertEqual(lines.map(\.text), ["第一句", "第一句", "第二句"])
        XCTAssertEqual(lines.count, 3)
    }

    func testLRCRejectsInvalidTimeBoundariesAndEmptyTimedText() {
        guard case .timed(let lines, _) = LRCParser.parse("[00:60.00]坏\n[00:01.00]好\n[00:02.00]") else {
            return XCTFail("expected valid line")
        }
        XCTAssertEqual(lines, [LyricLine(start: 1, text: "好")])
        XCTAssertEqual(LRCParser.parse("[00:01.00]"), .empty)
    }

    func testLRCClassifiesPlainInstrumentalAndEmpty() {
        XCTAssertEqual(LRCParser.parse("第一句\n第二句"), .plainText("第一句\n第二句"))
        XCTAssertEqual(LRCParser.parse("此歌曲为没有填词的纯音乐"), .instrumental)
        XCTAssertEqual(LRCParser.parse(""), .empty)
        guard case .timed(let lines, _) = LRCParser.parse("[00:01.00]只有一句") else {
            return XCTFail("expected timed")
        }
        XCTAssertEqual(lines, [LyricLine(start: 1, text: "只有一句")])
    }

    func testQRCWordTimingParserDoesNotInventTimestamps() {
        let raw = "[1000,2000]你(1000,200)好(1200,300) (1500,100)世界(1600,400)"
        let lines = QRCParser.parse(raw)
        XCTAssertEqual(lines.count, 1)
        XCTAssertEqual(lines[0].startMilliseconds, 1000)
        XCTAssertEqual(lines[0].durationMilliseconds, 2000)
        XCTAssertEqual(lines[0].words.map(\.text), ["你", "好", " ", "世界"])
        XCTAssertEqual(lines[0].words.map(\.startMilliseconds), [1000, 1200, 1500, 1600])
        XCTAssertEqual(lines[0].words.map(\.durationMilliseconds), [200, 300, 100, 400])
    }
}
